# M09-B01 · End-to-End Pipeline
> Video: Module 9, Build 1. Watch it first, then follow along here.

## What you'll learn
- One path for every change: a pull request, required checks (lint, unit, integration against real PostgreSQL and
  Redis), one image per service built once, scanned (SBOM + Trivy gate) and pushed by digest.
- **Promote, don't rebuild**: staging updates itself after every merge and is smoke-tested; production takes only a
  release that passed staging, digest for digest, after a releaser approves.
- **Blue-green deploys that protect users**: check the new colour before the switch, watch the error rate after it,
  and switch back on their own on an error spike. Plus a one-click rollback.
- Four staged failures and which stage stops each one; reading DORA numbers (lead time, change fail rate, recovery
  time) from the deployment record.

## Before you start
- Everything from Module 8 and M09-L01/L02: GitHub account, `gh`, Docker, `jq`, `ssh`, Python 3 (for the traffic
  generator).
- Two **public** GitHub repositories you create: `allcsvideos-platform` (the code) and `deploy-production` (production's
  gate). Public, because required reviewers on Environments and branch protection are free there.
- **Two servers GitHub can reach over SSH.** [`hosts/`](hosts/) runs `staging-01` and `prod-01` (each with its own Docker
  engine, an nginx load balancer, PostgreSQL + Redis, and blue/green colours) on one Docker machine. Run it on a small
  cloud VM with ports 2201-2202, 8001-8002 and 8081-8082 open. **The VM costs money while it runs**; delete it after.
- Approvals need a **second GitHub account** (you can't approve your own pull request). Solo? Set required approvals to 0
  and act as both Priya and Rahul.
- In the commands below, `L=<path-to-this-lesson-folder>` and `<host>` is your VM's address.
- The video ran all of this on the local Gitea lab (with a CI Docker daemon and the two hosts). Gitea ignores
  environment rules and issues no OIDC tokens, so production's gate there was write access to `deploy-production`.
  On GitHub you add an Environment with required reviewers.
- Not in this release: the Java API, gateway and catalog (they join the same way later).

## Files in this folder
| File | What it is |
|---|---|
| `starter/allcsvideos-platform/` | The repo at 1.7.0: `copilot/` (FastAPI, tests, migrations, `/version`), `storefront/`, `VERSION`, `deploy/staging.env`. No pipeline yet |
| `stages/pipeline-1-checks.yml` | Step 1: lint, unit, integration |
| `stages/pipeline-2-image.yml` | Step 2: + the `image` job (both services, SBOM, Trivy gate, push to GHCR from main only) |
| `.github/workflows/pipeline.yml` | Step 3, final: + `deploy-staging` (blue-green) and `smoke-staging` |
| `deploy-production/.github/workflows/deploy.yml` | Production: gate on the staging record, then blue-green deploy + smoke tests (Environment `production`) |
| `deploy-production/.github/workflows/rollback.yml` | Production rollback: one field, the reason |
| `deploy-production/production.env` | Production's app settings, sent with every deploy |
| `changes/1.8.0/` ... `changes/1.9.2/` | The staged changes: 1.8.0 (real questions), 1.9.0 + `1.9.0-bug` (prices in rupees), 1.9.1 (breaks under traffic), 1.9.2 (fix) |
| `changes/production-currency/production.env` | The config-drift fix: `CURRENCY=INR` for production |
| `hosts/` | The environment host kit: `Dockerfile`, `compose.yaml` (one colour), `data.yaml`, `lb/site.conf`, `deploy-agent`, `up.sh`, `down.sh` |
| `users/traffic.py` | Simulated users: 20 requests/s against production's load balancer |

## Follow along

1. **The servers.** On the VM (with this folder copied to it):
   ```bash
   cd $L/hosts
   bash up.sh ghcr.io/<your-user>
   ```
   On each host: the load balancer, the database and Redis are running, no app yet. The deploy agent accepts
   `deploy`, `rollback`, `smoke` and `status`, nothing else. A deploy goes to the **idle** colour: expand-only
   migrations, start storefront + Copilot and wait for healthy, check that colour directly (storefront `/healthz`,
   `/version` with both digests, a real question, a price from the database), then rewrite one line in `route.conf`,
   `nginx -t` and a graceful reload, then **watch** the load balancer log every 2 s: more than 5% failed in the last
   5 s (at least 10 requests) -> switch straight back. Staging watches 6 s, production 20 s (`*-host.env`).

2. **The repo at 1.7.0.**
   ```bash
   cp -R $L/starter/allcsvideos-platform ~/allcsvideos-platform
   cd ~/allcsvideos-platform
   git init -b main && git add -A && git commit -m 'allcsvideos platform 1.7.0'
   gh repo create allcsvideos-platform --public --source . --push
   ```

3. **Step 1: the checks.**
   ```bash
   mkdir -p .github/workflows
   cp $L/stages/pipeline-1-checks.yml .github/workflows/pipeline.yml
   git add -A && git commit -m 'pipeline: checks' && git push
   ```
   `lint` (hadolint on both Dockerfiles, ruff, mypy), `unit` (report kept as an artifact) and `integration` (real
   PostgreSQL and Redis service containers with health checks, migrations, then the integration tests) start
   together and pass (about 2 minutes in the video).

4. **Step 2: the image.**
   ```bash
   cp $L/stages/pipeline-2-image.yml .github/workflows/pipeline.yml
   git commit -am 'pipeline: one image per service' && git push
   ```
   `image` needs all three checks. Tags: `sha-<short>`, the full version and `major.minor`. For each service: build
   once into a file, SBOM, Trivy gate (a fixable CRITICAL fails the job); only on main is it pushed (with the build
   cache) and the digest becomes a job output. On a PR it is built and scanned, never pushed. The run keeps the SBOMs
   and `release.json` as an artifact. Make both new GHCR packages (`copilot`, `storefront`) **public** so the hosts
   can pull them.

5. **Step 3: staging.** Repository **Settings > Secrets and variables > Actions**: variables `STAGING_HOST` = `<host>`,
   `STAGING_SSH_PORT` = `2201`, `STAGING_URL` = `http://<host>:8001`, `STAGING_KNOWN_HOSTS` = the `[<host>]:2201
   ssh-ed25519 ...` line from `up.sh`; secret `STAGING_SSH_KEY` = contents of `hosts/keys/staging-01`.
   ```bash
   cp $L/.github/workflows/pipeline.yml .github/workflows/pipeline.yml
   git commit -am 'pipeline: blue-green to staging, then smoke tests' && git push
   ```
   `deploy-staging` (push to main only, one at a time) sends both digests over SSH with `deploy/staging.env` on stdin;
   `smoke-staging` tests through the load balancer like a user and records passed/failed. In the deploy log the agent
   starts blue, checks it, switches (about 100 ms) and watches. Check:
   ```bash
   curl -s http://<host>:8001/version | jq .
   curl -s http://<host>:8081/versions.json | jq -c '.history[0] | {run, version, revision, result, smoke}'
   ```

6. **Step 4: production, in its own repo.**
   ```bash
   cp -R $L/deploy-production ~/deploy-production
   cd ~/deploy-production
   git init -b main && git add -A && git commit -m 'production deploys: by release, staging-verified only'
   gh repo create deploy-production --public --source . --push
   ```
   In `deploy-production`: variables `STAGING_RECORD_URL` = `http://<host>:8081/versions.json`, `PROD_HOST`,
   `PROD_SSH_PORT` = `2202`, `PROD_URL` = `http://<host>:8002`, `PROD_RECORD_URL` = `http://<host>:8082/versions.json`,
   `PROD_KNOWN_HOSTS` (port 2202 line). **Settings > Environments > New environment `production`**: required
   reviewers (the releasers), and the environment secret `PROD_SSH_KEY` = `hosts/keys/prod-01`.
   `deploy.yml` asks for the release (short commit) and a reason; its gate refuses anything that didn't pass the
   staging smoke tests and hands over the exact digests staging ran. Promote 1.7.0:
   ```bash
   REV=$(curl -s http://<host>:8081/versions.json | jq -r '.history[0].revision')
   gh workflow run deploy.yml -R <you>/deploy-production -f revision=$REV -f reason='Release 1.7.0'
   ```
   Approve the waiting job (**Review deployments**). Blue goes live on prod-01 and the smoke tests pass.

7. **Step 5: guard rails.** In `allcsvideos-platform`, branch protection (or a ruleset) on `main`: require a pull
   request with **1 approval**, **dismiss stale approvals** when new commits are pushed, required status checks
   `lint`, `unit`, `integration`, `image`, and no bypassing. Give `deploy-production` the same rule (PR + 1 approval),
   so production's settings change only through a reviewed PR. A direct push is now refused:
   ```bash
   cd ~/allcsvideos-platform
   echo '# test' >> VERSION && git commit -qam 'direct push test' && git push      # refused: protected branch
   git reset -q --hard origin/main
   ```

8. **Run it: Priya's 1.8.0, from PR to production.** Lukas asked "What is Docker?" and got no answer: the question
   mark stuck to the word.
   ```bash
   git switch -c ask-real-questions
   cp -R $L/changes/1.8.0/. .
   git diff --stat
   git commit -am 'ask: understand real questions (1.8.0)'
   git push -u origin ask-real-questions
   gh pr create --title 'Copilot 1.8.0: understand real questions' \
     --body 'Words are now split on anything that is not a letter or digit.'
   ```
   Four required checks go green; the two deploy jobs are **skipped** (a PR never deploys). A second account approves
   (`gh pr review --approve`), then merge (`gh pr merge --merge`). The merge runs the full pipeline; staging runs
   1.8.0 with smoke passed. Start the users, then promote while they are on:
   ```bash
   python3 $L/users/traffic.py http://<host>:8002/ 95 /tmp/rel180 &
   REV=$(curl -s http://<host>:8081/versions.json | jq -r '.history[0].revision')
   gh workflow run deploy.yml -R <you>/deploy-production -f revision=$REV -f reason='Release 1.8.0: Copilot understands real questions'
   ```
   After approval: green starts next to blue while users stay on blue, passes all four checks, the switch takes about
   0.1 s, the watch sees zero failures for 20 s, and blue stays up with 1.7.0 for an instant rollback. In the video:
   1900 requests during the deploy, zero failed (see `/tmp/rel180.txt` when the generator finishes). Compare:
   ```bash
   for p in 8001 8002; do curl -s http://<host>:$p/version | jq -c '{environment, version, colour, copilot, storefront}'; done
   ```
   Same version, same two digests, byte for byte.

9. **Break 1 (staged): a bad pull request.** 1.9.0 shows prices in rupees; the bug version drops the thousands
   separator:
   ```bash
   git switch main && git pull && git switch -c prices-in-rupees
   cp -R $L/changes/1.9.0/. . && cp -R $L/changes/1.9.0-bug/. .
   git add -A && git commit -m 'price: show prices in the site currency (1.9.0)'
   git push -u origin prices-in-rupees
   gh pr create --title 'Copilot 1.9.0: prices in rupees' --body 'CURRENCY=INR shows prices in rupees; added to staging.env too.'
   ```
   `unit` fails (expected the rupee sign and `1,299`, got `1299`), `image` is skipped, the PR is blocked
   (`gh pr merge` is refused). Fix it (one format code, a comma), push, approve, merge:
   ```bash
   cp $L/changes/1.9.0/copilot/app/money.py copilot/app/money.py
   git diff
   git commit -am 'money: thousands separator' && git push
   ```

10. **Break 2 (staged): config drift.** 1.9.0 refuses to start without `CURRENCY`; staging got it in the PR, production
    didn't. Start users and promote 1.9.0 (as in step 8). On prod-01 the agent starts the idle colour, Copilot keeps
    restarting (`entrypoint: CURRENCY is not set (INR, EUR or USD)`), it never becomes healthy, so **no switch**: users
    stay on 1.8.0 with zero failures, and the workflow fails before its smoke tests. Find the drift and fix it the same
    safe way:
    ```bash
    cd ~/deploy-production && git pull
    diff <(grep -v '^#' ~/allcsvideos-platform/deploy/staging.env) <(grep -v '^#' production.env)
    git switch -c currency
    cp $L/changes/production-currency/production.env production.env
    git commit -am 'production: CURRENCY=INR (needed by 1.9.0)' && git push -u origin currency
    gh pr create --title 'production: CURRENCY=INR' --body 'Copilot 1.9.0 refuses to start without CURRENCY. Staging has it; production did not.'
    ```
    Approve, merge, deploy again: the new colour is healthy, passes its checks and takes over; prices come back in
    rupees.

11. **Break 3 (staged): fails only under real traffic.** 1.9.1 adds the course level to answers; tests and staging pass
    (the smoke test only asks about docker, and DevOps has a level).
    ```bash
    cd ~/allcsvideos-platform && git switch main && git pull && git switch -c course-level
    cp -R $L/changes/1.9.1/. .
    git commit -am 'ask: say the course level (1.9.1)' && git push -u origin course-level
    gh pr create --title 'Copilot 1.9.1: answers say the course level' \
      --body 'Answers now say the level, e.g. Try the DevOps course (beginner to advanced).'
    ```
    Merge after approval, start users, promote. Green passes all checks and goes live; two seconds later the watch
    sees an error spike (in the video 13 of 37 requests, 35%) and switches back to blue in about 0.2 s. Only DevOps
    has a level in the index; every other question crashed with a `KeyError`. One short red blip (15 failed out of
    1600), no outage. Fix with 1.9.2 (a level only when there is one, plus a test that asks about graphs) the normal
    way, on a branch `level-optional`: `cp -R $L/changes/1.9.2/. .`, commit `ask: courses without a level (1.9.2)`,
    PR, approve, merge, promote. It goes live with zero failures.

12. **Break 4: a rollback drill.** Some problems throw no errors; a human decides.
    ```bash
    gh workflow run rollback.yml -R <you>/deploy-production -f reason='rollback drill'
    ```
    After approval the agent checks the standby colour and switches (about 0.3 s). The old colour stays up, so even
    the rollback can be undone.

13. **The DORA numbers from the record.**
    ```bash
    curl -s http://<host>:8082/versions.json | jq -c '.history[] | [.run, .kind, .version, .result, .switch_ms, .smoke]'
    ```
    Lead time for 1.8.0 in the video: 9 min 18 s from commit to production; most of it machines, and the two waits are
    people. Five deploys switched traffic, one was switched back: change fail rate 1 in 5, recovery 2 s (the watch did
    it). The refused 1.9.0 never reached a user, so it isn't a failure. These are one session's numbers, not a
    benchmark; definitions at dora.dev.

## Common mistakes
- Requiring checks that a path filter can skip (the PR then waits forever). This pipeline has no path filters.
- Rebuilding for production instead of promoting the digest staging tested.
- Production settings edited by hand on the server (drift). Change them through a reviewed PR, like `CURRENCY`.
- Smoke tests that only ask one easy question. 1.9.1 passed them; the post-switch watch caught it.
- Non-expand-only migrations: both colours share one database, so schema changes must work for the old release too.

## Clean up
```bash
bash $L/hosts/down.sh                      # on the VM; then delete the VM
gh repo delete <you>/deploy-production
gh repo delete <you>/allcsvideos-platform  # optional
```
Delete the GHCR packages `copilot` and `storefront` (package settings) if you don't need them.

## Next
[M10-L01 · The Cloud Model](../../cloud/m10-l01-the-cloud-model/)
