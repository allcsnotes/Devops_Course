# M18-L03 · Supply-Chain Security
> Video: Module 18, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- The six links of a software supply chain (source, dependencies, build, base images, registry, deploy) and a real attack on each (xz 2024, Codecov 2021, the Trivy tag swap of 2026).
- Lock files with exact versions and hashes for every package, transitive ones included, and how to scan and fix them.
- SBOMs in CycloneDX and SPDX with Syft, and scanning an SBOM with Grype.
- Signing image digests with cosign, catching a swapped tag, and attaching the SBOM as a signed attestation.
- Keyless signing (OIDC + Fulcio + Rekor) and SLSA build levels with BuildKit provenance.

## Before you start
- Docker Desktop with buildx, `curl` and `jq`. The tools run as pinned containers with `--network host`: on Docker
  Desktop, turn on host networking (Settings > Resources > Network) so they can reach the lab registry on `localhost:5001`.
- Course Copilot as [M18-L01](../m18-l01-shift-left/) left it (this folder brings its own copy in `copilot/`).
- Free port 5001 (the lab registry; 5000 is often taken by macOS AirPlay).
- Pinned versions: `python:3.13.16-slim` (by digest in 1.7.0), `registry:3.1.2`, Trivy 0.76.0, uv 0.13.4, Syft 1.55.0,
  Grype 0.121.0, cosign 3.1.4 (all images pinned by digest, see `tools.sh`).

## Files in this folder
| File | What it is |
|---|---|
| `tools.sh` | Shell functions `trivy`, `uv`, `syft`, `grype`, `cosign`: each runs the tool's pinned image |
| `copilot/` | Course Copilot 1.6.0: the app, `Dockerfile` (1.6.0) and `requirements.txt` with 4 direct pins, no lock |
| `copilot/vulns.tpl` | A one-line-per-finding Trivy template |
| `stages/requirements.in` | Direct dependencies only, with the lowest versions accepted |
| `stages/requirements.v170.txt` | The lock the video ended with (every package, version and hash) |
| `stages/Dockerfile.v170` | 1.7.0: base pinned by digest, `pip install --require-hashes` |
| `tamper/` | STAGED: a different image to push under the same tag (its extra file only prints a line) |

## Follow along
1. Load the tools and build 1.6.0. Four pins in the file, many more packages in the image.
   ```bash
   cd copilot
   source ../tools.sh
   docker build -q --build-arg APP_VERSION=1.6.0 -t allcsvideos/copilot:1.6.0 .
   cat requirements.txt
   docker run --rm --entrypoint python allcsvideos/copilot:1.6.0 -c 'import importlib.metadata as m; print(sorted(d.name.lower() for d in m.distributions()))'
   ```
   Nineteen packages; fifteen are transitive (h11 via uvicorn, starlette via FastAPI...).

2. A lock file. Keep only the direct dependencies in `requirements.in`, and let uv compile the lock. Staged: resolve
   as if it were 1 April 2025, a lock nobody updated since.
   ```bash
   cp ../stages/requirements.in requirements.in
   cat requirements.in
   uv pip compile requirements.in --generate-hashes --exclude-newer 2025-04-01 -q -o requirements.txt
   grep -c "==" requirements.txt
   grep -A4 "^h11==" requirements.txt
   ```
   ```
   18
   h11==0.14.0 \
       --hash=sha256:8f19fbbe99e72420ff35c00b27a34cb9937e902a8b810e2c88300c6f0a3b699d \
       --hash=sha256:e3fe4ac4b851c468cc8363d500db52c2ead036020723024a109d37346efaa761
       # via uvicorn
   ```

3. Scan the lock.
   ```bash
   trivy fs -q --scanners vuln --severity HIGH,CRITICAL --format template --template @vulns.tpl .
   trivy fs -q --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 . > /dev/null; echo "exit code: $?"
   trivy fs -q --scanners vuln --format json . | jq '.Results[].Vulnerabilities[] | select(.PkgName=="h11") | {PkgName, InstalledVersion, FixedVersion, Severity, Title, PrimaryURL}'
   ```
   ```
   anyio      4.9.0      CVE-2026-63374       CRITICAL  fixed in 4.14.2
   certifi    2025.1.31  GHSA-6q48-6c7w-9gw2  CRITICAL  fixed in 2026.10.19
   h11        0.14.0     CVE-2025-43859       CRITICAL  fixed in 0.16.0
   starlette  0.46.1     CVE-2025-62727       HIGH      fixed in 0.49.1
   urllib3    2.3.0      CVE-2025-66418       HIGH      fixed in 2.6.0
   ...
   exit code: 1
   ```
   Twelve findings in the video, every one in a transitive package. Your list will differ as the databases grow.

4. Fix only what the CVE names, then re-lock (note the difference `--upgrade` makes).
   ```bash
   uv pip compile requirements.in --generate-hashes --upgrade-package h11 -q -o requirements.txt
   grep -A1 "^h11==" requirements.txt
   uv pip compile requirements.in --generate-hashes -q -o requirements.txt
   grep -E "^(h11|starlette)==" requirements.txt
   uv pip compile requirements.in --generate-hashes --upgrade -q -o requirements.txt
   grep -E "^(anyio|certifi|fastapi|h11|requests|starlette|urllib3|uvicorn)==" requirements.txt
   trivy fs -q --scanners vuln --format template --template @vulns.tpl .
   trivy fs -q --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 . > /dev/null; echo "exit code: $?"
   ```
   Without `--upgrade`, uv keeps starlette 0.46.1. With it (in the video): anyio 4.15.1, starlette 1.9.0, urllib3 2.8.0,
   no findings, `exit code: 0`. Your versions will be newer: that's fine. To use exactly the video's lock:
   `cp ../stages/requirements.v170.txt requirements.txt`.

5. Hashes enforced at build time. Use the 1.7.0 Dockerfile (base pinned by digest, `--require-hashes`), then stage a
   swapped package: change one character in both h11 hashes.
   ```bash
   cp ../stages/Dockerfile.v170 Dockerfile
   cp ../stages/requirements.v170.txt requirements.txt
   sed -i.bak 's/63cf8bbe7522/63cf8cbe7522/; s/4e35b956cf45/4e35b957cf45/' requirements.txt
   docker build --progress plain --build-arg APP_VERSION=1.7.0 -t allcsvideos/copilot:tampered . 2>&1 | grep -E "DO NOT MATCH|Expected sha256|Got  "
   ```
   ```
   ERROR: THESE PACKAGES DO NOT MATCH THE HASHES FROM THE REQUIREMENTS FILE. ...
           Expected sha256 4e35b957cf45792e4caa5885e69fba00bdbc6ffafbfa020300e549b208ee5ff1
                Got        63cf8bbe7522de3bf65932fda1d9c2772064ffb3dae62d55932da54b31cb6c86
   ```
   Put the real lock back and build:
   ```bash
   mv requirements.txt.bak requirements.txt
   docker build -q --build-arg APP_VERSION=1.7.0 -t allcsvideos/copilot:1.7.0 .
   docker run --rm --entrypoint python allcsvideos/copilot:1.7.0 -c 'import h11, starlette; print(h11.__version__, starlette.__version__)'
   ```
   `0.16.0 1.9.0`.

6. The lab registry and the 1.7.0 release, with SLSA provenance from BuildKit.
   ```bash
   docker run -d --name supplychain-registry -p 127.0.0.1:5001:5000 registry:3.1.2
   IMAGE=localhost:5001/allcsvideos/copilot
   docker buildx build -q --provenance=mode=max,version=v1 --sbom=false --build-arg APP_VERSION=1.7.0 -t $IMAGE:1.7.0 --push .
   DIGEST=$(docker buildx imagetools inspect $IMAGE:1.7.0 --format '{{.Manifest.Digest}}')
   echo $DIGEST
   docker buildx imagetools inspect $IMAGE:1.7.0 | grep -E 'MediaType|Platform'
   ```
   An image index: your platform's image plus one attestation (`unknown/unknown`). The digest is the name we sign.

7. An SBOM of exactly that digest, in both formats, then scan the SBOM with Grype.
   ```bash
   syft --version
   syft -q registry:$IMAGE@$DIGEST -o cyclonedx-json=copilot-1.7.0.cdx.json -o spdx-json=copilot-1.7.0.spdx.json
   jq '{bomFormat, specVersion, components: (.components | length)}' copilot-1.7.0.cdx.json
   jq -c '[.components[].type] | group_by(.) | map({(.[0]): length}) | add' copilot-1.7.0.cdx.json
   jq '.components[] | select(.name=="h11") | {name, version, purl, licenses}' copilot-1.7.0.cdx.json
   jq '{spdxVersion, packages: (.packages | length)}' copilot-1.7.0.spdx.json
   grype -q sbom:copilot-1.7.0.cdx.json | head -20
   grype -q sbom:copilot-1.7.0.cdx.json | tail -n +2 | wc -l
   grype -q sbom:copilot-1.7.0.cdx.json | grep -c " python "
   grype -q sbom:copilot-1.7.0.cdx.json --only-fixed --fail-on high > /dev/null; echo "exit code: $?"
   ```
   In the video: CycloneDX 1.7 with 2,801 components (2,693 files, 106 libraries), `"purl": "pkg:pypi/h11@0.16.0"`,
   MIT; SPDX-2.3 with 108 packages; 161 Grype findings, all Debian packages of the base image (mostly "won't fix"),
   0 in Python, gate `exit code: 0`.

8. Sign the digest with a lab key pair. The password is a **fake** lab value; a real one never goes on screen or in CI logs.
   The empty signing config means: no public transparency log, no timestamp authority (this lab is offline).
   ```bash
   export COSIGN_PASSWORD='FAKE-lab-only-m18l03'
   cosign generate-key-pair
   ls -l cosign.*
   cosign signing-config create --out lab-signing-config.json
   cat lab-signing-config.json; echo
   cosign sign --key cosign.key --signing-config lab-signing-config.json --allow-http-registry -y $IMAGE@$DIGEST
   curl -s -i http://localhost:5001/v2/allcsvideos/copilot/referrers/$DIGEST | head -1
   curl -s http://localhost:5001/v2/allcsvideos/copilot/tags/list | jq .
   ```
   No referrers API (`404`), so cosign used the fallback tag `sha256-<digest>`.

9. Verify.
   ```bash
   cosign verify --key cosign.pub --insecure-ignore-tlog --allow-http-registry $IMAGE:1.7.0 > verify.json; echo "exit code: $?"
   jq '.[0].critical.image' verify.json
   ```
   `exit code: 0` and the signed payload names your digest. (The warning about skipping the log is true, and fine in a lab.)

10. **Staged tampering:** someone with push rights pushes a different image under the same tag.
    ```bash
    cat ../tamper/Dockerfile
    docker build -q -t $IMAGE:1.7.0 ../tamper
    docker push -q $IMAGE:1.7.0
    docker buildx imagetools inspect $IMAGE:1.7.0 --format '{{.Manifest.Digest}}'; echo
    cosign verify --key cosign.pub --insecure-ignore-tlog --allow-http-registry $IMAGE:1.7.0 > /dev/null; echo "exit code: $?"
    cosign verify --key cosign.pub --insecure-ignore-tlog --allow-http-registry $IMAGE@$DIGEST > /dev/null; echo "exit code: $?"
    docker run --rm --entrypoint /app/extra.sh $IMAGE:1.7.0
    ```
    ```
    Error: no signatures found
    exit code: 10
    exit code: 0
    staged lab change: this image was not built by the pipeline
    ```

11. The SBOM as a signed attestation on the good digest, and a rescan from the registry's copy.
    ```bash
    cosign attest --key cosign.key --signing-config lab-signing-config.json --allow-http-registry -y --type cyclonedx --predicate copilot-1.7.0.cdx.json $IMAGE@$DIGEST
    cosign verify-attestation --key cosign.pub --insecure-ignore-tlog --allow-http-registry --type cyclonedx $IMAGE@$DIGEST > att.json; echo "exit code: $?"
    jq '.payload | @base64d | fromjson | {_type, predicateType, subject: .subject[0].digest.sha256[0:12], components: (.predicate.components | length)}' att.json
    cosign verify-attestation --key cosign.pub --insecure-ignore-tlog --allow-http-registry --type cyclonedx $IMAGE:1.7.0 > /dev/null; echo "exit code: $?"
    jq '.payload | @base64d | fromjson | .predicate' att.json > sbom-from-registry.json
    grype -q sbom:sbom-from-registry.json --only-fixed --fail-on high > /dev/null; echo "exit code: $?"
    ```
    ```
    "predicateType": "https://cyclonedx.org/bom",
    "components": 2801
    Error: no matching attestations:
    exit code: 1
    ```

12. The provenance BuildKit attached (SLSA Build level 1: it exists, but nothing trusted signed it).
    ```bash
    docker buildx imagetools inspect $IMAGE@$DIGEST --format '{{json .Provenance}}' > prov.json
    jq '.SLSA.buildDefinition | {buildType, frontend: .externalParameters.request.frontend, args: .externalParameters.request.args}' prov.json
    jq -r '.SLSA.buildDefinition.resolvedDependencies[].uri | split("?")[]' prov.json
    ```
    ```
    pkg:docker/python@3.13.16-slim
    digest=sha256:cf50a4f6ac4f026458b08d5222023d700ac806410dff5e9ca8728fa44f2b850f&platform=linux%2Farm64
    ```

13. Pitfall: signing by tag. cosign warns, then signs whatever the tag points to now: the tampered image.
    ```bash
    cosign sign --key cosign.key --signing-config lab-signing-config.json --allow-http-registry -y $IMAGE:1.7.0
    cosign verify --key cosign.pub --insecure-ignore-tlog --allow-http-registry $IMAGE:1.7.0 > /dev/null 2>&1; echo "exit code: $?"
    ```
    `exit code: 0`, for the wrong image. Resolve the digest, sign the digest, deploy the digest.

## Key ideas
| | What it proves | Lab or real world |
|---|---|---|
| Key-pair signature | "this digest came from whoever holds cosign.key" | lab (step 8) |
| Keyless signature | identity from OIDC (e.g. `--certificate-identity` + `--certificate-oidc-issuer https://token.actions.githubusercontent.com`), short-lived Fulcio certificate, Rekor log | needs internet and a real OIDC identity: diagram only |
| SLSA Build L1 / L2 / L3 | provenance exists / signed by a hosted platform / hardened, isolated platform | GitHub artifact attestations: L2, L3 with a shared reusable workflow |

## Common mistakes
- **Signing by tag.** Always resolve the digest first, sign the digest, deploy the digest.
- **Scanning once.** New CVEs arrive daily: keep the signed SBOM and rescan it on a schedule.
- **Ignoring transitive dependencies.** All twelve findings were in packages nobody named. Lock, hash, scan the lock.
- **Private keys in CI variables.** Prefer keyless signing with OIDC, or a KMS key CI can use but never read.
- **Trusting your own tools.** Pin cosign, Syft, Grype and Trivy by digest too.

## Clean up
```bash
docker rm -f supplychain-registry
docker image rm allcsvideos/copilot:1.6.0 allcsvideos/copilot:1.7.0 localhost:5001/allcsvideos/copilot:1.7.0 2>/dev/null
docker volume rm supplychain-trivy-cache supplychain-uv-cache supplychain-grype-cache 2>/dev/null
rm -f cosign.key cosign.pub lab-signing-config.json *.cdx.json *.spdx.json verify.json att.json sbom-from-registry.json prov.json requirements.in
git checkout -- Dockerfile requirements.txt   # if you cloned the course repo: back to 1.6.0
```

## Next
[M18-L04 · Kubernetes Security](../m18-l04-kubernetes-security/)
