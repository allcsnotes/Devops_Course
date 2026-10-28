# M08-L04 · Building and Pushing Images
> Video: Module 8, Lesson 4. Watch it first, then follow along here.

## What you'll learn
- Why only CI pushes images: one recipe (the Dockerfile), one place (a clean runner), and every tag traceable to a
  commit. Pull requests build, but never push.
- An image job with Buildx: login, `metadata-action` tags and OCI labels, test stage exported as a report, a Trivy SBOM
  and a CRITICAL gate **before** the push, then a multi-arch push (amd64 + arm64) with a registry cache.
- Where the Docker daemon comes from in CI (host socket vs a separate daemon vs remote BuildKit vs a fresh VM).
- Registry cache (`mode=max`) and what it costs; emulation (QEMU) cost and native arm64 runners.
- Artifacts: keep the test report and the SBOM with the run.

## Before you start
- Docker Desktop, Git, a GitHub account, and the GitHub CLI `gh` (handy for artifacts and runs).
- Modules 6 and 7 (multi-stage Dockerfile, Trivy, tags and labels). This lesson uses its own small repo,
  **course-copilot** (Course Copilot 1.5.0, as Module 7 left it): [`starter/course-copilot/`](starter/course-copilot/).
- In the commands below, `L=<path-to-this-lesson-folder>`.
- The video ran on a local Gitea with its package registry, a separate "Docker in Docker" daemon for jobs and a
  `prod-01` server, all in Docker. Here you use GitHub-hosted runners (a fresh VM with Docker per job) and **GHCR**
  (`ghcr.io`). The basic offline lab is in [`../m08-l01-what-ci-is/gitea-lab/`](../m08-l01-what-ci-is/gitea-lab/README.md),
  but it does not include the CI Docker daemon or registry setup this lesson needs.

## Files in this folder
| File | What it is |
|---|---|
| `starter/course-copilot/` | Course Copilot 1.5.0: FastAPI app, tests, Dockerfile (build/test/runtime), `.trivyignore.yaml` |
| `changes/Dockerfile` | The Dockerfile change: pytest writes a JUnit report, new `test-report` stage keeps only that file |
| `.github/workflows/image.yml` | The image pipeline for GitHub + GHCR |
| `bench/bench.py` | A tiny Python loop to measure emulation cost (optional) |

## Follow along

1. **Make the course-copilot repo** (it is v1.5.0):
   ```bash
   cp -R $L/starter/course-copilot ~/course-copilot
   cd ~/course-copilot
   git init -b main && git add -A && git commit -m 'Course Copilot 1.5.0'
   git tag -a v1.5.0 -m 'Course Copilot 1.5.0'
   gh repo create course-copilot --public --source . --push
   ```
   Do **not** build and push an image from your laptop. The video's hook is exactly that: a 1.5.1 built from an
   uncommitted working copy on Apple silicon, so the registry had only arm64 and production failed with
   `no matching manifest for linux/amd64`, with no commit to trace it to.

2. **Registry login, the GitHub way.** No extra account or token: the job's `GITHUB_TOKEN` gets
   `permissions: packages: write`, and the image is `ghcr.io/<owner>/course-copilot`. (On Gitea, the job token can't
   push packages, so the video used a `ci-bot` account with a `write:package` token stored as the secret
   `REGISTRY_TOKEN`.)

3. **Add the workflow and the Dockerfile change.**
   ```bash
   mkdir -p .github/workflows
   cp $L/.github/workflows/image.yml .github/workflows/image.yml
   cp $L/changes/Dockerfile Dockerfile
   git status --short
   git diff Dockerfile
   ```
   Read `image.yml` top to bottom: triggers (main, `v*` tags, PRs into main); `PUSH` is true unless the event is a
   pull request, and every step that writes to the registry checks it; Buildx with BuildKit pinned to v0.33.1;
   `metadata-action` with `latest` off and tags `sha`, branch, PR, `{{version}}`, `{{major}}.{{minor}}`; the `Test`
   build of the `test-report` target; `Build for the scan` to a tar file (nothing pushed); Trivy 0.76.0 pinned by
   digest for the SBOM and the gate (`--exit-code 1 --severity CRITICAL`); then both platforms with `cache-from` /
   `cache-to` (`mode=max`, never written by PRs), `provenance` and `sbom`. On GitHub you also need
   `docker/setup-qemu-action` because the runner is amd64 and must emulate arm64.
   ```bash
   git add -A
   git commit -m 'ci: build, scan and push the Copilot image'
   git push
   ```

4. **Run 1 (cold).** In the job log you should see: the login `Login Succeeded` (the token never appears), two tags
   `main` and `sha-<short sha>`, labels `org.opencontainers.image.revision` (the full commit), `source` and
   `version=main`; the cache import `not found` (first run); the tests `2 passed`; the scan prints nothing (exit 0,
   gate open); one manifest list pushed under both tags, then the cache exported. The last step prints:
   ```
   MediaType: application/vnd.oci.image.index.v1+json
   ...
     Platform:    linux/amd64
     ...
     Platform:    linux/arm64
   ```
   plus two attestation manifests. The run page lists two artifacts: **sbom** and **test-report**. Your package is
   under your profile's **Packages** tab.

5. **A pull request builds but never pushes.**
   ```bash
   git switch -c ask-hint
   sed -i.bak 's/Try asking about docker!/Try asking about docker or kubernetes!/' app/main.py && rm app/main.py.bak
   git commit -am 'ask: suggest kubernetes too'
   git push -u origin ask-hint
   gh pr create --base main --head ask-hint --title 'ask: suggest kubernetes too' --body ''
   ```
   The `pull_request` run skips **Log in to the registry**, tags it `pr-1` (GitHub builds the test merge commit; Gitea
   built the branch head, `pr-1-head`), and builds both platforms with no push and no `cache-to`. If your package is
   private, the cache import fails with `401 Unauthorized` (the run never logged in), so PRs pay with a cold build.
   Why not log in on PRs? A PR can change the workflow itself, and with a push token in the job its author could use
   it. From forks, secrets are not passed and `GITHUB_TOKEN` is read-only.

6. **Merge: run 3 (warm).**
   ```bash
   gh pr merge --merge --delete-branch
   git switch main && git pull
   ```
   In the push step, every layer before the changed `app/` folder says `CACHED`, taken from the registry. The video's
   numbers: push step 23 s cold -> 13 s warm; job 1 min 34 -> 1 min 4; Docker's build summary 29% -> 47% of steps
   cached. The cache costs space: `mode=max` kept every layer of every stage for both platforms (108 MiB, more than
   each 50 MiB image). Look at the `buildcache` tag size in the package's versions.

7. **Optional: what does emulation cost?** On your laptop (Apple silicon shown):
   ```bash
   cd $L/bench
   uname -m
   docker run --rm --platform linux/arm64 python:3.12.15-slim python -c "$(cat bench.py)"
   docker run --rm --platform linux/amd64 python:3.12.15-slim python -c "$(cat bench.py)"
   ```
   The video: `0.24 s` native arm64, `0.45 s` amd64 through Rosetta, and `6.93 s` under QEMU (about 29 times
   slower). For heavy builds use native runners instead: GitHub has arm64 Linux runners (`ubuntu-24.04-arm`, free
   on public repos); build each platform on its own runner and merge them into one manifest list.

8. **Break it, on purpose: the scan gate.** Rahul pins an old `h11` and pushes to main:
   ```bash
   cd ~/course-copilot
   echo 'h11==0.14.0' >> requirements.txt
   git diff
   git commit -am 'deps: pin h11 to 0.14.0'
   git push
   ```
   Tests pass, the image builds, the SBOM is uploaded, then the gate:
   ```
   Total: 1 (CRITICAL: 1)
   │ h11 (METADATA) │ CVE-2025-43859 │ CRITICAL │ fixed  │ 0.14.0  │ 0.16.0  │ h11: h11 accepts some malformed Chunked-Encoding bodies │
   Error: Process completed with exit code 1.
   ```
   The push step is **skipped**: there is no `sha-<that commit>` tag in the registry, and `main` still points at the
   last good build. The failed run's SBOM is kept: it records exactly what would have shipped. Revert:
   ```bash
   git revert --no-edit HEAD
   git push
   ```

9. **Release.**
   ```bash
   git log --oneline -6
   git tag -a v1.6.0 -m 'Course Copilot 1.6.0'
   git push origin v1.6.0
   ```
   `metadata-action` now gives three tags: `1.6.0`, `1.6`, `sha-<short sha>`, and the version label says `1.6.0`.

10. **Download the artifacts and look inside.**
    ```bash
    mkdir -p ~/artifacts && cd ~/artifacts
    gh run download <run-id-of-the-tag-run> -R <your-user>/course-copilot
    jq -r ".bomFormat, .specVersion, (.components | length)" sbom/sbom.cdx.json
    jq -c '.components[] | select(.name=="fastapi") | {name, version, purl}' sbom/sbom.cdx.json
    grep -o '<testsuite [^>]*>' test-report/junit.xml | cut -c1-96
    ```
    You should see `CycloneDX`, `1.7`, about 104 components, `{"name":"fastapi","version":"0.154.0","purl":"pkg:pypi/fastapi@0.154.0"}`
    and `tests="2"` with `failures="0"`.

11. **Pull by digest and run it, like prod-01.** Get the digest from the run's last step (or the package page). If the
    package is private, either make it public (package **Settings > Change visibility**) or log in with
    `docker login ghcr.io` using a token you create with `read:packages`.
    ```bash
    docker pull --platform linux/amd64 ghcr.io/<owner>/course-copilot@sha256:<digest>
    docker pull ghcr.io/<owner>/course-copilot@sha256:<digest>
    docker run -d --name copilot -p 8000:8000 ghcr.io/<owner>/course-copilot@sha256:<digest>
    sleep 4; curl -s http://localhost:8000/health; echo
    docker inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}} {{index .Config.Labels "org.opencontainers.image.version"}}' copilot
    ```
    You should see `{"status":"ok","version":"1.6.0","courses":5}` and `<full commit sha> 1.6.0`: the labels answer
    "which commit is this?". The attestation manifests hold SLSA provenance and an SBOM; they are not signatures
    (signing with cosign comes in Module 18).

## Common mistakes
- **Pushing from pull requests or forks.** Never give a PR a push token: build, don't push, gate the push on the event.
- **Tags without traceability.** `latest` or `fix` tells nobody anything. Tag with the commit, add semver on releases,
  label revision and source.
- **Cache bloat.** A `mode=max` cache can outgrow the images. One cache tag per image, plus a cleanup rule.
- **QEMU slowness.** Emulated steps can be many times slower; cross-compile heavy steps or use native runners.
- **Leaking registry tokens.** Keep them in secrets, never echo them, scope them to packages, never hand them to
  untrusted jobs.
- **Mounting the Docker socket in untrusted jobs.** The socket is root on the host. Use a separate daemon, remote
  BuildKit, or a fresh VM per job.
- `.trivyignore.yaml` accepts one CVE until `2026-12-31` with a reason; after that date the gate counts it again.

## Clean up
```bash
docker rm -f copilot
docker rmi $(docker images --filter "reference=ghcr.io/*/course-copilot" -q) 2>/dev/null
rm -rf ~/artifacts
```
Keep the `course-copilot` repo for the next lessons. To delete the images later: your profile > **Packages** >
course-copilot > **Package settings** > Delete this package (this also removes the `buildcache` tag).

## Next
[M08-L05 · Secrets and OIDC](../m08-l05-secrets-and-oidc/)
