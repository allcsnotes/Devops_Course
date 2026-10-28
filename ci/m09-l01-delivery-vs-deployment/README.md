# M09-L01 · Delivery vs Deployment
> Video: Module 9, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- **Continuous delivery** (every change is releasable; production is a one-click business decision) vs **continuous
  deployment** (every green change goes to production automatically).
- Environments and parity: staging is the rehearsal; the same compose file everywhere, only a small env file differs;
  config comes from outside the image.
- **Build once, deploy many**: staging and production run the same image digest. Promote, don't rebuild.
- A delivery pipeline: build -> deploy to staging automatically -> smoke tests -> a human approval -> the same digest
  to production, with a record of what runs where.
- Rollback = deploying the previous digest.

## Before you start
- Your `course-copilot` repo and its GHCR package from [M08-L04](../m08-l04-building-and-pushing-images/), at 1.6.0.
  Make the package **public** (package **Settings > Change visibility**) so the servers can pull it.
- Docker, Git, `gh`, `jq`, `ssh`.
- **Two servers.** GitHub-hosted runners must reach them over SSH. This folder has a kit,
  [`hosts/`](hosts/), that runs `staging-01` and `prod-01` as two containers on one Docker machine. For the full
  GitHub pipeline, run it on a machine GitHub can reach (for example one small cloud VM with ports 2201-2202,
  8001-8002 and 8081-8082 open; Module 10 shows how). **A VM costs money while it runs**; delete it when you're done.
  No VM? Run the kit on your laptop and do steps 1-3 and 9 by hand (you play the pipeline over SSH).
- Required reviewers on a GitHub Environment are free only in **public** repos (Free, Pro and Team plans).
- In the commands below, `L=<path-to-this-lesson-folder>`.
- The video ran all of this on the local Gitea lab with a separate CI Docker daemon. Gitea ignores environment rules,
  so the video gated production with a separate `deploy-production` repository only the releasers team could run.
  Here you use GitHub's own gate: an Environment with required reviewers.

## Files in this folder
| File | What it is |
|---|---|
| `changes/` | Copilot 1.6.0 with a new `/version` endpoint: `app/main.py`, `Dockerfile` (`APP_REVISION`), `tests/test_health.py`, `VERSION` |
| `.github/workflows/pipeline.yml` | build -> deploy-staging -> smoke-staging (GitHub Environment `staging`) |
| `.github/workflows/deploy-production.yml` | Manual: gate on the staging record, then deploy + smoke in Environment `production` |
| `hosts/Dockerfile` | The one environment host image: own Docker engine, SSH, deployment record on :8080 |
| `hosts/compose.yaml` | The same Compose file on both hosts: image by digest, `env_file: app.env` |
| `hosts/staging.env`, `hosts/production.env` | The only difference: `APP_ENV=staging` / `APP_ENV=production` |
| `hosts/deploy-agent` | The only thing the deploy key may run: `deploy`, `smoke`, `status` |
| `hosts/sshd_config`, `hosts/host-entrypoint.sh` | Key-only SSH as `deploy`, no forwarding; start-up |
| `hosts/up.sh`, `hosts/down.sh` | Start/remove both hosts, make one deploy key per host |

## Follow along

1. **Start the two servers** (on the VM, or on your laptop):
   ```bash
   cd $L/hosts
   bash up.sh ghcr.io/<your-user>/course-copilot
   docker ps --filter label=course=devops --format 'table {{.Names}}\t{{.Image}}'
   ```
   Both hosts run the same image, `env-host`. Look inside:
   ```bash
   docker exec staging-01 cat /srv/app/compose.yaml /srv/app/app.env
   docker exec prod-01 cat /srv/app/app.env
   docker exec staging-01 cat /home/deploy/.ssh/authorized_keys
   ```
   `APP_ENV=staging` vs `APP_ENV=production` is the only difference. The deploy key starts with
   `restrict,command="/usr/local/bin/deploy-agent"`: whatever the pipeline sends, SSH runs only the agent, with no
   shell and no forwarding. The agent knows `deploy`, `smoke` and `status`, and refuses anything that isn't a real
   `sha256:` digest:
   ```bash
   ssh -i keys/staging-01 -p 2201 -o StrictHostKeyChecking=accept-new deploy@localhost 'bash -i'
   ssh -i keys/staging-01 -p 2201 deploy@localhost status
   ```
   You should see `refused: deploy-agent only knows deploy, smoke and status`, then an empty record.

2. **The app learns `/version`.** In your `course-copilot` repo:
   ```bash
   cd ~/course-copilot && git pull
   cp $L/changes/app/main.py app/main.py
   cp $L/changes/tests/test_health.py tests/test_health.py
   cp $L/changes/Dockerfile Dockerfile
   cp $L/changes/VERSION VERSION
   git diff --stat
   ```
   `/version` reports the version, the Git revision, the environment and the digest.

3. **Settings: GitHub Environments.** Repo **Settings > Environments**:
   - `staging`: variables `HOST` (the VM's address), `SSH_PORT` = `2201`, `URL` = `http://<host>:8001`,
     `KNOWN_HOSTS` = the `[<host>]:2201 ssh-ed25519 ...` line from `up.sh` (with your host's address), and the secret
     `SSH_KEY` = the contents of `hosts/keys/staging-01` (the private key).
   - `production`: `HOST`, `SSH_PORT` = `2202`, `URL` = `http://<host>:8002`, `KNOWN_HOSTS` for port 2202, secret
     `SSH_KEY` = `hosts/keys/prod-01`. Protection rules: **Required reviewers** (add yourself and/or a teammate; up to
     six people or teams, one approval is enough), and **Prevent self-review** if you have a second reviewer.
     **Deployment branches**: `main` only.
   - A repository variable `STAGING_RECORD_URL` = `http://<host>:8081/versions.json`.
   Environment secrets reach a job only after its environment's rules pass. The production key is never available to
   the staging jobs.

4. **The pipeline: deploy every green build to staging, then smoke-test it.**
   ```bash
   cp $L/.github/workflows/pipeline.yml $L/.github/workflows/deploy-production.yml .github/workflows/
   git rm -q .github/workflows/image.yml
   git add -A
   git commit -m 'cd: deploy every green build to staging, then smoke-test it'
   git push
   ```
   `build` is Module 8 as before (test, Trivy gate, push) and now outputs the pushed **digest** and the version.
   `deploy-staging` (push to main only, `concurrency: staging`) asks the agent to deploy that digest. `smoke-staging`
   checks health within 30 s, that `/version` reports this exact digest in `staging`, and one real question, then
   records `passed` or `failed` on staging. Three jobs in order; in the video about 1 min 19 s from push to a tested
   staging. The deploy log:
   ```
   deploy-agent on staging-01 (staging): ghcr.io/<you>/course-copilot@sha256:...
    Container copilot-copilot-1 Started
   recorded: staging now runs 1.6.0 (sha256:...)
   ```
   Ask staging yourself:
   ```bash
   curl -s http://<host>:8001/version | jq .
   curl -s http://<host>:8081/versions.json | jq .current
   ```
   You should see `"environment": "staging"`, the digest, and `"smoke": "passed"`.

5. **Promote to production: the approval.** Read the digest from the staging record, then run the gate workflow
   (web: **Actions > deploy-production > Run workflow**, or):
   ```bash
   D=$(curl -s http://<host>:8081/versions.json | jq -r .current.digest); echo $D
   gh workflow run deploy-production.yml -f digest=$D -f reason='First production release through the pipeline: 1.6.0'
   ```
   `gate` prints who, what and why, and checks the staging record. `deploy-production` then waits: **Review
   deployments** on the run page. Approve it. The job pulls the **same digest** to prod-01 and smoke-tests production.
   Inputs go into environment variables before any script uses them, so text typed into the form can never become a
   command. Compare both servers:
   ```bash
   for p in 8001 8002; do curl -s http://<host>:$p/version; echo; done
   ```
   Same version, revision and digest; only `environment` differs. Built once, deployed twice. (Someone without
   permission to approve sees the waiting run but cannot approve it. In the video, Priya's API dispatch to the Gitea
   repo was refused: `user should have a permission to write to a repo`.)

6. **A normal day: 1.7.0.**
   ```bash
   sed -i.bak 's/Try asking about docker!/Try asking about docker or kubernetes!/' app/main.py && rm app/main.py.bak
   echo 1.7.0 > VERSION
   git commit -am 'ask: suggest kubernetes too (1.7.0)'
   git push
   ```
   Built, deployed to staging and smoke-tested with nobody touching anything. Promote it as in step 5. The time from
   commit to production is your change lead time; the wait for the human is usually most of it.

7. **Break it, on purpose: an image that can't start (1.7.1).**
   ```bash
   sed -i.bak 's|COURSE_INDEX=/app/data/courses.json|COURSE_INDEX=/app/data/course.json|' Dockerfile && rm Dockerfile.bak
   echo 1.7.1 > VERSION
   git commit -am 'Dockerfile: tidy up (1.7.1)'
   git push
   ```
   Unit tests pass (they read the file from the source folder), the scan passes, the image is pushed and deployed to
   staging. Then `smoke-staging`: `staging is not healthy after 30 s`; the other checks are skipped and
   **Mark failed on staging** records it. On the host:
   ```bash
   docker exec staging-01 docker ps -a --format "table {{.Names}}\t{{.Status}}"
   docker exec staging-01 docker logs --tail 2 copilot-copilot-1
   ```
   `Restarting`, and `entrypoint: course index /app/data/course.json not found`. Now try to promote the current
   staging digest anyway (step 5 commands): the gate refuses in seconds and production is untouched:
   ```
   refused: sha256:... never passed the staging smoke tests
   ```
   Fix it and push:
   ```bash
   sed -i.bak 's|COURSE_INDEX=/app/data/course.json|COURSE_INDEX=/app/data/courses.json|' Dockerfile && rm Dockerfile.bak
   git commit -am 'Dockerfile: fix the course index path'
   git push
   ```

8. **Rollback drill.** The production record lists what ran there, newest first:
   ```bash
   curl -s http://<host>:8082/versions.json | jq -c '.history[] | [.version, .digest[7:19], .smoke]'
   D=$(curl -s http://<host>:8082/versions.json | jq -r '.history[1].digest')
   gh workflow run deploy-production.yml -f digest=$D -f reason='rollback drill'
   ```
   Approve it: production answers 1.6.0 within seconds. No rebuild, no laptop: the old image was still in the
   registry under its digest. Then release the fixed 1.7.1 the same way (step 5).

9. **Which version is where?**
   ```bash
   curl -s http://<host>:8082/versions.json | jq -c '.history[] | [.deployed_at, .version, .digest[7:19], .run, .smoke]'
   curl -s http://<host>:8081/versions.json | jq -c '.history[] | [.deployed_at, .version, .digest[7:19], .run, .smoke]'
   ```
   Staging includes the failed 1.7.1. GitHub keeps its own audit trail too: **Actions** (who ran each production
   deploy, who approved it) and the **Deployments** page per environment.

   No VM? With the hosts on your laptop you can still practise the agent by hand, as the pipeline would:
   ```bash
   ssh -i $L/hosts/keys/staging-01 -p 2201 deploy@localhost deploy sha256:<a digest from your GHCR package> run-manual
   curl -s localhost:8001/version
   ssh -i $L/hosts/keys/staging-01 -p 2201 deploy@localhost smoke sha256:<same digest> passed
   ssh -i $L/hosts/keys/staging-01 -p 2201 deploy@localhost status
   ```

## Common mistakes
- **Environment drift.** Someone fixes production by hand, or staging gets a different database version; then a green
  staging proves nothing. Change servers only through code and the pipeline.
- **Rebuilding per environment.** Two builds are two different images. Build once, promote the digest.
- **Approval as a rubber stamp.** Give the approver the evidence (digest, smoke result, changes) and prevent
  self-reviews.
- **No smoke tests.** Starting a container says nothing about whether it works; today the smoke test caught an image
  every other check passed.
- **Manual steps outside the pipeline.** One hand-run command and the pipeline no longer describes production.

## Clean up
```bash
bash $L/hosts/down.sh          # on the machine that runs the hosts; then delete the VM if you made one
```
Delete the `SSH_KEY` secrets (the keys no longer exist) and, if you like, the two Environments. Keep `course-copilot`.

## Next
[M09-L02 · Deployment Strategies](../m09-l02-deployment-strategies/)
