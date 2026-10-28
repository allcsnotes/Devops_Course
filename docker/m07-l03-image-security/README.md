# M07-L03 · Image Security
> Video: Module 7, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- What CVEs, CVSS scores and fix statuses (fixed, affected, will not fix) mean, and why a finding is not the same as an exploitable app.
- Scan images with Trivy: filter to fixable highs and criticals, gate on the exit code, check Dockerfiles (`trivy config`) and secrets.
- Record an accepted risk in `.trivyignore.yaml` with a reason, a name and an expiry date.
- Fix an old image at the source: a current pinned base rebuilt with `--pull`, bumped dependency pins, a `.dockerignore`, a non-root user.
- Write and query SBOMs (CycloneDX and SPDX) with Trivy and Syft, and rescan a stored SBOM.
- Limit the damage at run time: non-root user, read-only root with tmpfs, `--cap-drop ALL`, `no-new-privileges`, seccomp, limits, never `--privileged`; the same in Compose.

## Before you start
- Docker Desktop (the video used 4.79, engine 29.5.3, on Apple silicon) and a bash/zsh terminal (on Windows use WSL or Git Bash).
- `curl`. `jq` is optional: `tools.sh` gives you a `jq` that runs from its image.
- Disk space: the full Python image is large, and Trivy's database is about 130 MB.
- The Copilot and storefront Dockerfiles are the ones from [M07-L01](../m07-l01-small-fast-images/); the non-root user and health check come from [M06-L04](../m06-l04-the-dockerfile-line-by-line/).
- Nothing gets installed: Trivy (`aquasec/trivy:0.76.0`) and Syft (`anchore/syft:v1.54.1`) run from images pinned by tag and digest.

**Your numbers will differ.** Trivy's database changes every day and base image tags get rebuilt, so your totals will not match the video exactly. The shape (old base: hundreds, current slim base: far fewer, zero criticals) is what matters.

## Files in this folder
| File | What it is |
|------|------------|
| `tools.sh` | Shell functions `trivy`, `syft`, `jq` that run the pinned tool images (`source ./tools.sh`) |
| `copilot-proto/` | The 2023 Copilot prototype: `FROM python:3.9.16-slim-bullseye`, runs as root, old pins, no `.dockerignore` |
| `copilot-proto/make-fake-env.sh` | Writes `copilot-proto/.env` with a FAKE GitHub-style token for the secret scan |
| `copilot/` | Copilot 1.5.0 from M07-L01: `Dockerfile` (slim, multi-stage), `Dockerfile.full`, `Dockerfile.distroless` |
| `storefront/` | The storefront: `Dockerfile` (stock nginx, root) and `Dockerfile.unprivileged` (nginx-unprivileged, uid 101, port 8080) |
| `stages/proto-*` | Each version of the prototype's Dockerfile and requirements (v0 = 2023, v1 = new base, v2 = new pins, v3 = non-root + health check) |
| `stages/proto.dockerignore` | The `.dockerignore` added to the prototype in the fix |
| `stages/trivyignore.v1.yaml`, `trivyignore.v2-expired.yaml` | The exception file, valid and already expired |
| `hardened/compose.yaml` | Copilot and the storefront run hardened, sharing an `x-hardened` block |

## Follow along

### 1. Build the images
```bash
source ./tools.sh

cd copilot
docker build -t copilot:full -f Dockerfile.full --build-arg APP_VERSION=1.5.0 .
docker build -t copilot:1.5.0 --build-arg APP_VERSION=1.5.0 .
docker build -t copilot:distroless -f Dockerfile.distroless .
cd ../storefront
docker build -t storefront:2 .
docker build -t storefront:3 -f Dockerfile.unprivileged .
cd ../copilot-proto
./make-fake-env.sh                  # FAKE token in .env, for step 4
docker build -q -t copilot:0.9 .
```

### 2. First scans
```bash
docker volume create --label course=devops trivy-cache
trivy image copilot:0.9
```
The first run downloads the vulnerability database (about 129 MB) into the volume. Then, in the log and the report:
```
WARN  This OS version is no longer supported by the distribution  family="debian" version="11.7"
WARN  The vulnerability detection may be insufficient because security updates are not provided
│ copilot:0.9 (debian 11.7)   │   debian   │       571       │
```
The summary lists the OS target, then one target per Python package metadata file, then one table per target. Now today's image:
```bash
cd ../copilot
trivy image -q copilot:1.5.0 | grep Total
trivy --version
```
```
Total: 166 (UNKNOWN: 3, LOW: 61, MEDIUM: 58, HIGH: 44, CRITICAL: 0)
Total: 12 (UNKNOWN: 0, LOW: 2, MEDIUM: 10, HIGH: 0, CRITICAL: 0)
```
`trivy --version` shows when the database was built (`UpdatedAt`) and the next one (`NextUpdate`): a scan is a snapshot.

### 3. Read and filter the findings
Compare all four Copilot images:
```bash
for t in full 0.9 1.5.0 distroless; do
  echo "== $t"; trivy image -q copilot:$t | grep Total
done
```
In the video: full 4,072 (16 critical), prototype 571 (13 critical), 1.5.0 on slim 166, distroless 162. The full image's criticals are in development libraries Copilot never uses; distroless barely beats slim because its Python comes from Debian packages, while the slim image compiles Python itself.

The prototype's criticals, and one CVE in detail:
```bash
trivy image -q --scanners vuln --severity CRITICAL copilot:0.9
trivy image -q --format json copilot:0.9 \
  | jq '.Results[0].Vulnerabilities[] | select(.VulnerabilityID=="CVE-2023-45853")
        | {PkgName, Status, Severity, nvd: .CVSS.nvd.V3Score, redhat: .CVSS.redhat.V3Score}'
```
Look at the status column: `libexpat1` is `fixed` (a rebuild on a patched base clears it), `zlib1g` and `libdb5.3` are `will_not_fix`. The zlib CVE scores 9.8 at the NVD and 5.3 at Red Hat; Trivy prefers the distribution's rating.

How many have a fix, and what the 44 highs in 1.5.0 really are:
```bash
trivy image -q --scanners vuln --format json copilot:0.9 \
  | jq -c '[.Results[].Vulnerabilities[]?.Status] | group_by(.) | map({(.[0]): length}) | add'
trivy image -q --scanners vuln --severity HIGH --format json copilot:1.5.0 \
  | jq -r '[.Results[].Vulnerabilities[]? | .Title | split(":")[0]] | group_by(.) | map("\(length) \(.[0])") | .[]'
```
```
{"affected":287,"fix_deferred":56,"fixed":230,"will_not_fix":20}
36 util-linux
```
36 of the 44 highs are in util-linux tools (mount, nsenter) Copilot never runs. Not exploitable through the app, but every tool left in the image is an attacker's tool once they are in.

Now filter, and make a gate:
```bash
trivy image -q --severity HIGH,CRITICAL copilot:0.9 | grep -B3 Total
trivy image -q --severity HIGH,CRITICAL --ignore-unfixed copilot:0.9 | grep -B3 Total
trivy image -q --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 copilot:0.9 > /dev/null; echo "exit code: $?"
trivy image -q --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 copilot:1.5.0 > /dev/null; echo "exit code: $?"
```
```
Total: 151 (HIGH: 138, CRITICAL: 13)      <- OS, high + critical
Total: 72 (HIGH: 64, CRITICAL: 8)         <- only the ones with a fix
exit code: 1
exit code: 0
```
That exit code is what stops a pipeline in Module 8.

### 4. Dockerfiles and secrets
```bash
cd ../copilot-proto
trivy config -q .
cd ../copilot
trivy config -q . | grep -E "Dockerfile|DS-"
docker image inspect --format '{{.Config.User}}' copilot:distroless
```
The prototype: `Tests: 27 (SUCCESSES: 25, FAILURES: 2)`, `DS-0002 (HIGH)` (no `USER`, runs as root) and `DS-0026` (LOW, no health check). In `copilot/`, `Dockerfile.distroless` gets DS-0002 although its `nonroot` base runs as `65532`: a false positive, because the check reads the text, not the base. One explicit `USER` line fixes it and documents the intent.

Secrets (the `.env` from `make-fake-env.sh`, FAKE):
```bash
cd ../copilot-proto
trivy fs -q --scanners secret .
trivy image -q --scanners secret copilot:0.9
```
```
CRITICAL: GitHub (github-pat)
 .env:3 (offset: 87 bytes)
...
 /app/.env:3 (offset: 87 bytes) (added by 'COPY . . # buildkit')
```
There is no `.dockerignore`, so `COPY . .` shipped the token inside the image. If it were real: revoke it first, then fix the build. Anyone who pulled the image has it.

### 5. An exception that expires
`CVE-2026-16742` (systemd-homed) shows up twice in 1.5.0, in `libsystemd0` and `libudev1`. Read `stages/trivyignore.v1.yaml`: the ID, a statement saying why (with a name and date), and `expired_at: 2026-12-31`.
```bash
cd ../copilot
trivy image -q --severity HIGH,CRITICAL copilot:1.5.0 | grep Total
cp ../stages/trivyignore.v1.yaml .trivyignore.yaml
trivy image -q --severity HIGH,CRITICAL --ignorefile .trivyignore.yaml copilot:1.5.0 | grep Total
trivy image -q --severity HIGH,CRITICAL --ignorefile .trivyignore.yaml --show-suppressed copilot:1.5.0 | grep -A12 Suppressed
cp ../stages/trivyignore.v2-expired.yaml .trivyignore.yaml       # expiry moved to 2026-10-01, already past
trivy image -q --severity HIGH,CRITICAL --ignorefile .trivyignore.yaml copilot:1.5.0 | grep Total
cp ../stages/trivyignore.v1.yaml .trivyignore.yaml
```
44, then 42 with the two suppressed rows and the statement listed, then 44 again once the rule has expired. (If your CVE list differs, put an ID from your own scan in the file.)

### 6. Fix the prototype
**Base.** Python 3.9 is past end of life and Debian 11 is out of support. Pin a current base and build with `--pull`:
```bash
cd ../copilot-proto
cp ../stages/proto-Dockerfile.v1 Dockerfile        # FROM python:3.12.15-slim
docker build -q --pull -t copilot:0.9.1 .
trivy image -q --scanners vuln copilot:0.9.1 | grep -B3 Total
```
OS findings: 571 down to 166, zero critical. Python still 14 (Starlette from the old FastAPI pin has three highs).

**Dependencies.** FastAPI 0.95.0 to 0.154.0, uvicorn to 0.54.0:
```bash
cp ../stages/proto-requirements.v2 requirements.txt
docker build -q -t copilot:0.9.2 .
trivy image -q --scanners vuln copilot:0.9.2 | grep -B3 Total
```
Python drops to 6: medium findings in pip itself, a build tool the app does not need at run time.

**Secrets and root.** A `.dockerignore`, a user with ID 10001, a `USER` line and a health check:
```bash
cp ../stages/proto-Dockerfile.v3 Dockerfile
cp ../stages/proto.dockerignore .dockerignore
docker build -q -t copilot:0.9.3 .
trivy image -q copilot:0.9.3 | grep -B3 Total
trivy config -q . | grep -A2 Target
docker run --rm copilot:0.9.3 id
```
No secrets target any more, `Dockerfile │ dockerfile │ 0`, and `uid=10001(copilot)`. Same app, three small changes.

Pin plus update is the rule: official images rebuild a tag like `3.12.15-slim` when Debian ships fixes, so rebuild regularly with `--pull`, and let a bot (Dependabot, Renovate) bump the pins (Module 8).

### 7. SBOMs
```bash
cd ../copilot
trivy image -q --format cyclonedx --output copilot-1.5.0.cdx.json copilot:1.5.0
du -h copilot-1.5.0.cdx.json
jq '.bomFormat, .specVersion, (.components | length)' copilot-1.5.0.cdx.json
jq '.components[] | select(.name=="fastapi") | {name, version, purl, licenses}' copilot-1.5.0.cdx.json
trivy image -q --format spdx-json --output copilot-1.5.0.spdx.json copilot:1.5.0
jq '.spdxVersion, (.packages | length)' copilot-1.5.0.spdx.json
jq '.packages[] | select(.name=="fastapi") | {name, versionInfo, licenseConcluded}' copilot-1.5.0.spdx.json
syft -q copilot:1.5.0
```
You should see `"CycloneDX"`, `"1.7"`, about 104 components; fastapi `0.154.0` with `"purl": "pkg:pypi/fastapi@0.154.0"` and license `MIT`; `"SPDX-2.3"`; and Syft's table of `deb`, `python` and `binary` entries.

The payoff: a new xz advisory arrives. One query, no pull, no rescan:
```bash
jq -r '.components[] | select(.name=="liblzma5") | .name + " " + .version' copilot-1.5.0.cdx.json
trivy sbom -q copilot-1.5.0.cdx.json | grep -B3 Total
```
`liblzma5 5.8.1-1+deb13u1`, and scanning the SBOM gives the same totals as the image scan. Keep an SBOM with every release and rescan it as the database updates. (`docker scout quickview` does this too, but asks for a Docker login first.)

### 8. Run with less power
**Users.**
```bash
docker run --rm copilot:0.9 id
docker run --rm copilot:1.5.0 id
docker run --rm --user 10001:10001 python:3.12.15-slim id
```
`uid=0(root)`, then `uid=10001(copilot)`, then `uid=10001` with no name (that user is not in the image's passwd file).

**Read-only root filesystem.**
```bash
docker run --rm --read-only --entrypoint touch copilot:1.5.0 /tmp/cache
docker run --rm --read-only --tmpfs /tmp --entrypoint touch copilot:1.5.0 /tmp/cache && echo "written to /tmp"
docker run --rm --read-only storefront:2 2>&1 | tail -2
docker run -d --name web --read-only --tmpfs /var/cache/nginx --tmpfs /run -p 8080:80 storefront:2
sleep 2; curl -s -o /dev/null -w "%{http_code}\n" localhost:8080
docker rm -f web
```
`Read-only file system`, then `written to /tmp`; stock nginx fails with `mkdir() "/var/cache/nginx/client_temp" failed (30: Read-only file system)`, and serves `200` with tmpfs at its cache folder and `/run`.

**Capabilities.**
```bash
docker run --rm python:3.12.15-slim grep CapEff /proc/self/status
docker run --rm --cap-drop ALL python:3.12.15-slim grep CapEff /proc/self/status
docker run --rm --read-only --tmpfs /var/cache/nginx --tmpfs /run --cap-drop ALL storefront:2 2>&1 | tail -1
docker run -d --name web --read-only --tmpfs /var/cache/nginx --tmpfs /run \
  --cap-drop ALL --cap-add CHOWN --cap-add SETUID --cap-add SETGID -p 8080:80 storefront:2
sleep 2; curl -s -o /dev/null -w "%{http_code}\n" localhost:8080
docker rm -f web
```
`CapEff: 00000000a80425fb` (Docker's 14 default capabilities), then all zeros. nginx with none fails on `chown(... ) failed (1: Operation not permitted)`; adding back `CHOWN`, `SETUID`, `SETGID` gives `200`.

**Port 80.** Inside a container the unprivileged port start is 0, so any user may bind port 80. Restore 1024 and see what changes:
```bash
docker run --rm python:3.12.15-slim cat /proc/sys/net/ipv4/ip_unprivileged_port_start
docker run --rm --read-only --tmpfs /var/cache/nginx --tmpfs /run \
  --sysctl net.ipv4.ip_unprivileged_port_start=1024 \
  --cap-drop ALL --cap-add CHOWN --cap-add SETUID --cap-add SETGID storefront:2 2>&1 | tail -1
docker run -d --name web --read-only --tmpfs /var/cache/nginx --tmpfs /run \
  --sysctl net.ipv4.ip_unprivileged_port_start=1024 \
  --cap-drop ALL --cap-add CHOWN --cap-add SETUID --cap-add SETGID --cap-add NET_BIND_SERVICE \
  -p 8080:80 storefront:2
sleep 2; curl -s -o /dev/null -w "%{http_code}\n" localhost:8080
docker rm -f web
```
`bind() to 0.0.0.0:80 failed (13: Permission denied)`, then `200` with `NET_BIND_SERVICE`.

**The better design** needs none of this: the unprivileged nginx image, user 101, port 8080.
```bash
docker run -d --name web --read-only --tmpfs /tmp --cap-drop ALL -p 8080:8080 storefront:3
sleep 2; curl -s -o /dev/null -w "%{http_code}\n" localhost:8080
docker exec web id
docker rm -f web
```

**No new privileges, seccomp, and what `--privileged` does.**
```bash
docker run --rm python:3.12.15-slim grep -E "NoNewPrivs|Seccomp:" /proc/self/status
docker run --rm --security-opt no-new-privileges python:3.12.15-slim grep -E "NoNewPrivs|Seccomp:" /proc/self/status
docker info --format '{{.SecurityOptions}}'
docker run --rm --privileged python:3.12.15-slim grep -E "CapEff|Seccomp:" /proc/self/status
```
`NoNewPrivs` goes from 0 to 1; `Seccomp: 2` means filtering with Docker's default profile; `--privileged` gives `CapEff: 000001ffffffffff` and `Seccomp: 0`. Never in production.

### 9. One hardened run, then the same in Compose
```bash
docker run -d --name copilot \
  --user 10001:10001 --read-only --tmpfs /tmp \
  --cap-drop ALL --security-opt no-new-privileges \
  --memory 256m --cpus 0.5 --pids-limit 100 \
  -p 8000:8000 copilot:1.5.0
sleep 8; docker ps --filter name=copilot --format "{{.Names}}  {{.Status}}"
curl -s localhost:8000/health
docker exec copilot grep -E "CapEff|NoNewPrivs|Seccomp:" /proc/1/status
docker stats --no-stream --format '{{.Name}}  {{.MemUsage}}  {{.PIDs}} pids' copilot
docker rm -f copilot
```
```
copilot  Up 8 seconds (healthy)
{"status":"ok","version":"1.5.0","courses":5}
CapEff:	0000000000000000
NoNewPrivs:	1
Seccomp:	2
copilot  39.14MiB / 256MiB  2 pids
```
In Compose, `hardened/compose.yaml` puts `read_only`, `cap_drop`, `security_opt` and `tmpfs` in an `x-hardened` block; each service merges it with `<<: *hardened` and adds its own user and limits.
```bash
cd ../hardened
docker compose config
docker compose up -d
sleep 8; docker compose ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}"
curl -s localhost:8000/health
curl -s -o /dev/null -w "%{http_code}\n" localhost:8080
docker compose down
```
Both services show `read_only: true`, `cap_drop: [ALL]` and `no-new-privileges:true`; Copilot is healthy and the storefront answers `200`.

### 10. Scanning without the Docker socket (for CI)
```bash
cd ../copilot
docker save -o copilot-1.5.0.tar copilot:1.5.0
docker run --rm -v trivy-cache:/root/.cache -v "$PWD":/work -w /work \
  aquasec/trivy:0.76.0@sha256:2416d1f74045b57274df1a340eee6b510cacd73c66a6ccb8da092b117eb7d222 \
  image -q --input copilot-1.5.0.tar | grep Total
rm -f copilot-1.5.0.tar
```
Same totals as before, with no socket mounted.

## Common mistakes
- **Alert fatigue.** Thousands of findings and nobody reads any. Filter to fixable highs and criticals, gate on those, review the rest on a schedule.
- **Ignoring everything.** An ignore file that only grows is a scanner switched off. Every entry needs a reason, a name and an expiry date.
- **Scanning once.** The image does not change, the database does, every day. Rescan what is running, or its stored SBOM, on a schedule.
- **Secrets in images.** Scan for them, keep a `.dockerignore`, and if one leaks, rotate it. Removing it from the next build does not help.
- **Running as root because it is easier.** Most images run fine as a numeric user; where one does not (stock nginx), pick an unprivileged variant.
- **Trusting your tools blindly.** In March 2026 Trivy's own releases were compromised (the 0.69.4 binaries and the 0.69.4 to 0.69.6 images on Docker Hub); images pinned by digest were not affected. Pin tools by digest, and remember a mounted Docker socket gives the tool control of Docker.
- **Fewer findings is not always less risk** (distroless vs slim), and a `trivy config` finding can be a false positive (DS-0002 on the `nonroot` base).

## Clean up
```bash
cd ..                                   # back to this lesson folder
(cd hardened && docker compose down)
docker rm -f web copilot 2>/dev/null
docker rmi copilot:full copilot:0.9 copilot:0.9.1 copilot:0.9.2 copilot:0.9.3 copilot:1.5.0 copilot:distroless storefront:2 storefront:3
docker volume rm trivy-cache
rm -f copilot-proto/.env copilot-proto/.dockerignore copilot/.trivyignore.yaml copilot/*.json
git checkout -- copilot-proto/Dockerfile copilot-proto/requirements.txt   # back to the 2023 prototype (inside the course repo)
```
The pinned base and tool images (python, debian, distroless, node, nginx, trivy, syft, jq) stay in your cache; `docker rmi` them if you want the space back.

## Next
[M07-L04 · Registries and Tagging](../m07-l04-registries-and-tagging/)
