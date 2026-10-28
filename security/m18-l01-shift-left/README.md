# M18-L01 · Shift Left
> Video: Module 18, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- What "shift left" (and "shift everywhere") means, and why a fix costs more the later it happens.
- One security check per pipeline stage: threat model, pre-commit secret scan, SAST, SCA, DAST, image scan + SBOM, IaC scan.
- The OWASP Top 10 (2025) as an awareness map, and threat modelling with the four questions and STRIDE.
- Building a Gitea Actions workflow with four parallel gates: gitleaks, Semgrep, Trivy and Checkov.
- A gate policy that people keep trusting: what blocks, what warns, and exceptions that expire.

## Before you start
- Docker Desktop and `bash`, `curl`, `jq` on your laptop.
- The Gitea lab idea from Module 8 and the Terraform/Checkov project from Module 11 (this folder brings its own copy).
- Free port 3000 (Gitea).
- Pinned versions: `gitea/gitea:28.1.0`, `gitea/runner:5.1.1`, `gitea/runner-images:ubuntu-24.04-v26.10.01`,
  gitleaks 8.30.1 (`zricethezav/gitleaks:v8.30.1`), Semgrep 1.182.0, Trivy 0.76.0 (`aquasec/trivy:0.76.0` pinned by
  digest), Checkov 3.3.30 (`bridgecrew/checkov:3.3.30`), ZAP 2.17.0 (`zaproxy/zap-stable:2.17.0`), `python:3.13.16-slim`.
- Every key, token and password in this lab is **fake** and labelled so. The leaked AWS key and the GitHub token are
  staged on purpose so the scanners have something to find.

## Files in this folder
| File | What it is |
|---|---|
| `lab/lab.sh` | `up` (Gitea, the team machine, accounts, seeded repo, runner), `shell NAME`, `protect`, `down` |
| `lab/image/Dockerfile` | The team machine: Ubuntu 24.04 + git, curl, jq + gitleaks, Semgrep and Trivy (pinned) |
| `lab/runner/config.yaml` | Gitea runner config (jobs join the lab network) |
| `lab/ci.sh` | `runs`, `jobs RUN_ID`, `log JOB_ID`, `wait`: read workflow runs from the Gitea API |
| `lab/accounts.txt` | The lab accounts asha, priya, rahul (fake passwords) |
| `stages/s1`..`s3` | The repo history the lab seeds: Copilot 1.5.0, the infra, the leaked key (s2), the SQL-injection search + pyyaml 5.3.1 (s3) |
| `stages/s5/` | What Asha adds: `.gitea/workflows/security.yml`, `.githooks/pre-commit`, `.semgrep/sql-injection.yml`, `.trivyignore.yaml`, `docs/threat-model.md` |
| `stages/s6/` | Priya's and Rahul's fixes: the first (blocked) attempt, the env-var fix, the parameterised query, pyyaml 6.0.3, the three `.trivyignore.yaml` versions, `.gitleaksignore` |
| `stages/s7/copilot/app/mirror.py` | A new file with a fake GitHub token (the `--no-verify` test) |
| `stages/s8/copilot/Dockerfile` | The package-stage fix: pip removed from the runtime image |

## Follow along
1. Start the lab (the first run builds the team machine image, a few minutes).
   ```bash
   cd lab
   ./lab.sh up
   ```
   Gitea is at http://localhost:3000 (log in as `asha` / `fake-lab-pass-asha` to watch runs and pull requests).
   The team machine stands in for three laptops: `./lab.sh shell rahul`, `./lab.sh shell priya`, `./lab.sh shell asha`.
   Every command below runs in one of those shells unless it says "laptop".

2. **The late find** (rahul).
   ```bash
   git log --oneline --decorate -5
   gitleaks git -v --redact --no-banner .
   git tag --contains 2bce599
   git branch -r --contains 2bce599
   git rev-list --count 2bce599..v1.6.0
   ```
   ```
   RuleID:      aws-access-token
   File:        copilot/app/thumbnails.py
   Line:        6
   Commit:      2bce599f29fb83dc2007f0f0d0f9423f0dfed0d8
   Author:      Priya
   WRN leaks found: 1
   v1.6.0
   ```
   If your commit id differs, use the one gitleaks prints, here and in step 11.

3. **Asha adds the gates** on a branch and opens a pull request (asha).
   ```bash
   git switch -c security-gates
   cp -r /stages/s5/. .
   git status --short
   git add -A
   git commit -q -m 'security: gates for secrets, code, dependencies and infra'
   git push -q -u origin security-gates
   ```
   Read `.gitea/workflows/security.yml`: four jobs (`secrets`, `sast`, `deps`, `iac`). Then open a pull request from
   `security-gates` to `main` in the Gitea UI (title: "security: gates in the pipeline").

4. **Run 1** (laptop, in `lab/`):
   ```bash
   ./ci.sh wait
   ./ci.sh runs
   ./ci.sh jobs <RUN_ID>
   ```
   Three of four jobs fail, only `iac` passes: `secrets` (the key in commit 2bce599), `sast` (`sql-built-from-strings`
   on line 51 of `main.py`), `deps` (pyyaml 5.3.1, CVE-2020-14343, critical, fixed in 5.4). Read one with `./ci.sh log <JOB_ID>`.

5. **The pre-commit hook** (priya). Turn it on, then try to "rotate" the key by pasting a new (fake) one.
   ```bash
   git fetch -q && git switch -q security-gates
   cat .githooks/pre-commit
   git config core.hooksPath .githooks
   cp /stages/s6/thumbnails-attempt1.py copilot/app/thumbnails.py
   # fill in the FAKE secret (kept split in this repo so GitHub's push protection allows the course repo)
   sed -i "s/__FAKE_AWS_SECRET__/fAkE3nEw5dEmO7kEy2oNlY9f""Or4tHe8lAb6x2w1Q/" copilot/app/thumbnails.py
   git commit -am 'thumbnails: rotate the S3 key'
   git log --oneline -1
   ```
   ```
   RuleID:      aws-access-token
   Fingerprint: copilot/app/thumbnails.py:aws-access-token:6
   WRN leaks found: 1
   3b25847 (HEAD -> security-gates, origin/security-gates) security: gates for secrets, code, dependencies and infra
   ```
   No commit was made. The real fix reads the key from the environment:
   ```bash
   cp /stages/s6/copilot/app/thumbnails.py copilot/app/thumbnails.py
   git commit -am 'thumbnails: read the S3 key from the environment'
   ```
   `INF no leaks found`.

6. **SAST with Semgrep** (priya). The public pack first, then the team's own rule.
   ```bash
   semgrep scan --config p/python --metrics=off copilot/
   semgrep scan --config .semgrep/ --metrics=off --error copilot/
   echo $?
   ```
   The public pack downloads 151 rules and finds nothing for this pattern; our rule finds it:
   ```
   ❯❯❱ semgrep.sql-built-from-strings
          ❰❰ Blocking ❱❱
           51┆ rows = catalog_db().execute(sql).fetchall()
   1
   ```
   Apply the two-line fix (a `?` placeholder, the search text as a parameter) and scan again:
   ```bash
   cp /stages/s6/copilot/app/main.py copilot/app/main.py
   git diff --no-color copilot/app/main.py
   semgrep scan --config .semgrep/ --metrics=off --error copilot/
   echo $?
   git commit -qam 'search: pass the search text as a query parameter'
   ```
   `Ran 1 rule on 3 files: 0 findings.` and `0`.

7. **Dependencies with Trivy** (priya). The full report warns; the gate blocks HIGH/CRITICAL with a fix.
   ```bash
   trivy fs --scanners vuln --ignorefile .trivyignore.yaml -q copilot/
   trivy fs --scanners vuln --ignorefile .trivyignore.yaml --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 -q copilot/
   echo $?
   ```
   ```
   │ pyyaml   │ CVE-2020-14343 │ CRITICAL │ fixed  │ 5.3.1             │ 5.4           │
   │ requests │ CVE-2026-25645 │ MEDIUM   │        │ 2.32.4            │ 2.33.0        │
   1
   ```
   An exception that has expired doesn't help:
   ```bash
   cp /stages/s6/trivyignore-expired.yaml .trivyignore.yaml
   cat .trivyignore.yaml
   trivy fs --scanners vuln --ignorefile .trivyignore.yaml --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 -q copilot/ > /dev/null
   echo $?
   ```
   `1`. Then `stages/s6/trivyignore-valid.yaml` (expiry 2026-10-28) makes the gate pass. **If you run this after that
   date, edit `expired_at` to a date a week from today** to see it pass. Better than an exception: the one-line fix.
   ```bash
   cp /stages/s6/trivyignore-empty.yaml .trivyignore.yaml
   cp /stages/s6/copilot/requirements.txt copilot/requirements.txt
   git diff --no-color -U0 copilot/requirements.txt | tail -2
   trivy fs --scanners vuln --ignorefile .trivyignore.yaml --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 -q copilot/
   echo $?
   trivy fs --scanners vuln --ignorefile .trivyignore.yaml -q copilot/
   git commit -qam 'deps: pyyaml 6.0.3 (CVE-2020-14343)'
   git push -q
   ```
   `-pyyaml==5.3.1` / `+pyyaml==6.0.3`, exit code `0`; `requests` stays as a warning. New CVEs appear every day, so
   your Trivy report may list more than the video's.

8. **The old key in history** (rahul). It was revoked first; now record it with an expiry note.
   ```bash
   git config core.hooksPath .githooks
   git fetch -q && git switch -q security-gates && git pull -q
   cp /stages/s6/gitleaksignore .gitleaksignore
   cat .gitleaksignore
   gitleaks git --redact --no-banner .
   git add .gitleaksignore
   git commit -qm 'gitleaks: known 1.6.0 leak, key revoked'
   git push -q
   ```
   `INF no leaks found`. Run 2 (Priya's fixes) still fails `secrets`; run 3 is all green. Check with `./ci.sh runs` (laptop).

9. **Required checks and merge** (laptop), then merge the pull request in Gitea as asha:
   ```bash
   ./lab.sh protect
   ```
   ```
   protect main: HTTP 201
   ```

10. **Testing the gates** (priya). A hook is optional: `--no-verify` skips it. The pipeline is the backstop.
    ```bash
    git switch -q main && git pull -q && git switch -q -c priya/thumbnail-mirror
    cp /stages/s7/copilot/app/mirror.py copilot/app/
    git add copilot/app/mirror.py
    git commit --no-verify -qm 'thumbnails: mirror from the media repo'
    git push -q -u origin priya/thumbnail-mirror
    ```
    Open a pull request for it in Gitea: the `secrets` job fails on `github-pat`, `mirror.py`, line 4, and the merge waits.

11. **The test stage: DAST with ZAP** (laptop). Build the Copilot image from Priya's fixed clone, run it on the lab
    network as `copilot`, then run ZAP's baseline scan (passive: it watches, it doesn't attack).
    ```bash
    mkdir -p work && docker cp shiftleft-lab:/home/priya/allcsvideos-platform/copilot work/
    docker build -t shiftleft-copilot:1.6.1 work/copilot
    docker run -d --name shiftleft-copilot --network shiftleft-net --network-alias copilot shiftleft-copilot:1.6.1
    mkdir -p work/zap && chmod 777 work/zap
    docker run --rm --network shiftleft-net -v "$PWD/work/zap:/zap/wrk" zaproxy/zap-stable:2.17.0 zap-baseline.py -t http://copilot:8000
    echo $?
    ```
    ```
    WARN-NEW: X-Content-Type-Options Header Missing [10021] x 1
    WARN-NEW: Content Security Policy (CSP) Header Not Set [10038] x 1
    FAIL-NEW: 0	FAIL-INPROG: 0	WARN-NEW: 9	WARN-INPROG: 0	INFO: 0	IGNORE: 0	PASS: 58
    2
    ```
    Exit code 2 means warnings only: tickets for the edge (nginx), not a blocked release. Check the SQL fix from rahul's shell:
    ```bash
    curl -s 'http://copilot:8000/courses/search?q=dev'; echo
    curl -s --get http://copilot:8000/courses/search --data-urlencode "q=dev' OR '1'='1"; echo
    ```
    `[{"title":"DevOps","price":3999}]`, then `[]`: the text stays text.

12. **The package stage: scan the image** (laptop). Trivy runs from its pinned image with your Docker socket.
    ```bash
    TRIVY="docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.76.0@sha256:2416d1f74045b57274df1a340eee6b510cacd73c66a6ccb8da092b117eb7d222"
    $TRIVY image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 -q shiftleft-copilot:1.6.1; echo $?
    ```
    ```
    Total: 5 (HIGH: 4, CRITICAL: 1)
    │ certifi    │ GHSA-6q48-6c7w-9gw2 │ CRITICAL │ ...
    │ msgpack    │ ... setuptools ... urllib3 ...
    1
    ```
    All bundled inside pip, a build tool the app never uses. Remove pip from the runtime image and rescan:
    ```bash
    cp ../stages/s8/copilot/Dockerfile work/copilot/Dockerfile
    docker build -t shiftleft-copilot:1.6.1-nopip work/copilot
    $TRIVY image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 -q shiftleft-copilot:1.6.1-nopip; echo $?
    $TRIVY image --format cyclonedx -q shiftleft-copilot:1.6.1-nopip > work/sbom-1.6.1.cdx.json
    jq -r '.specVersion, (.components | length)' work/sbom-1.6.1.cdx.json
    ```
    Exit code `0`; the SBOM listed `1.7` and `107` components in the video.

## The gate policy (from the lesson)
| Finding | Blocks | Warns |
|---|---|---|
| Secrets | always | - |
| Code (SAST) | high-confidence rules (`ERROR`) | everything else |
| Dependencies and images | HIGH/CRITICAL with a fix | the rest, and anything without a fix yet |
| Exceptions | allowed only with an ID, a reason, a name and an expiry date | |

## Common mistakes
- **Hooks only.** `git commit --no-verify` skips them. Back them with the same checks in the pipeline.
- **Trusting one tool.** The registry packs found nothing here. Write rules for your own patterns and test that they fire.
- **Scanning only the requirements file.** The image held five more findings, inside pip.
- **Exceptions without expiry.** An ignore file that only grows is a scanner switched off.
- **Deleting a leaked secret and calling it done.** It's still in history and in every clone. Revoke and rotate first (lesson 2).
- **Shifting left and forgetting the right.** New vulnerabilities appear in running code: rescan, patch, watch.

## Clean up
```bash
docker rm -f shiftleft-copilot
./lab.sh down
rm -rf work
```

## Next
[M18-L02 · Secrets Management](../m18-l02-secrets-management/)
