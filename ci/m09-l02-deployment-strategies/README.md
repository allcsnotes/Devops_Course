# M09-L02 · Deployment Strategies
> Video: Module 9, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- The four strategies, run for real under traffic: **recreate**, **rolling update**, **blue-green**, **canary**.
- The four questions for each: how long are users affected, how fast is rollback, what does it cost in extra servers,
  and how many users see a bad version (the **blast radius**).
- Why draining, readiness checks and graceful shutdown (SIGTERM) make rolling updates zero-downtime.
- Why blue and green must never break each other's database (expand, migrate, contract).
- A canary guarded by a watchdog on real error rates, and why a health check can lie.

## Before you start
- Docker Desktop (the lab runs a privileged Docker-in-Docker "server"), about 2 GB free disk, a terminal.
- No GitHub needed: this lesson is all on your laptop.
- The images are pinned: `docker:29.5.3-dind`, `nginx:1.29.8-alpine`, `python:3.12.15-slim`
  (with `fastapi==0.154.0`, `uvicorn==0.54.0`).

## Files in this folder
| File | What it is |
|---|---|
| `lab/up.sh`, `lab/down.sh` | Start/remove the lab: `prod-01` with nginx + `blue-1..3` on 1.6.0, images 1.6.0 / 1.7.0 / 1.7.1 |
| `lab/users.sh` | Reset prod-01 and start 40 simulated requests a second; results in `lab/runs/` |
| `lab/users/traffic.py` | The traffic generator (70% questions, 30% `/version`; records status and `X-App-Version`) |
| `lab/app/` | Course Copilot per version: 1.6.0 (blue banner), 1.7.0 (purple, answers name the course), 1.7.1 (bad build: reads `level`) |
| `lab/lb/site.conf` | nginx: `proxy_pass http://$pool`, the access log the watchdog reads |
| `lab/deploy/lib.sh` | Helpers: `start_app`, `stop_app`, `wait_ready`, `lb_render`, `lb_route`, `lb_reload`, pool files |
| `lab/deploy/recreate.sh` | Strategy 0: stop all, start all |
| `lab/deploy/rolling.sh` | Strategy 1: one at a time with drain -> stop -> start -> ready -> back in |
| `lab/deploy/rolling-naive.sh` | The pitfall: no drain, no readiness wait |
| `lab/deploy/bluegreen.sh`, `lab/deploy/switch.sh` | Strategy 2: start + smoke-test green, then switch (and back) |
| `lab/deploy/canary.sh`, `lab/deploy/watchdog.sh` | Strategy 3: send N% to green; roll back when green's error rate > 5% |
| `lab/deploy/reset.sh` | Lab only: back to blue-1..3 on a version |
| `lab/host/Dockerfile` | The prod-01 image |

## Follow along

1. **Start the lab.**
   ```bash
   cd lab
   bash up.sh
   ```
   Open two terminals inside prod-01 as asha (one for deploys, one for the watchdog later):
   ```bash
   docker exec -it -u asha -w /home/asha/deploy prod-01 bash
   ```
   Ask through the load balancer:
   ```bash
   curl -si 'localhost/ask?q=docker'; echo
   ```
   You should see `HTTP/1.1 200 OK`, `x-app-version: 1.6.0` and `{"answer":"Try the DevOps course."}`. Look at the
   config: `cat /srv/lb/conf.d/upstreams.conf /srv/lb/conf.d/route.conf` (an upstream per pool; route.conf always says
   `blue`). Every change is `nginx -t`, then `nginx -s reload`: graceful, old workers finish their requests.

   Each run below: on your **laptop**, in `lab/`, start the users, then within a few seconds run the strategy in the
   prod-01 terminal. When the run ends, `cat runs/<name>.txt` shows one line per second.

2. **Strategy 0: recreate.**
   ```bash
   bash users.sh recreate 40          # laptop
   ./recreate.sh 1.7.0                # prod-01, about 10 s later
   ```
   ```
   02:18:34.680  stopping blue-1, blue-2, blue-3
   02:18:35.727  all stopped. starting 1.7.0
   02:18:36.327  all three ready on 1.7.0
   ```
   The app was gone for 1.65 s, but `runs/recreate.txt` shows about 4.5 s of `s502=40` (182 failed requests in the
   video). nginx's passive health check benched the servers for `fail_timeout` (5 s here, 10 s by default) after they
   failed. Fine for a batch job or an internal tool; for a site with users, every deploy is an outage.

3. **Strategy 1: rolling update.** First see what a drain looks like:
   ```bash
   source lib.sh; pool_set blue blue-1 down; lb_render; lb_reload
   grep server /srv/lb/conf.d/upstreams.conf
   pool_set blue blue-1; lb_render; lb_reload
   ```
   `blue-1` is marked `down`: no new requests. Now the real run:
   ```bash
   bash users.sh rolling 60           # laptop
   ./rolling.sh 1.7.0                 # prod-01
   ```
   Per instance: drain, wait 2 s, stop with SIGTERM, start the new version at the same address, wait until
   `/health` is 200 (or stop the rollout), put it back. About 3 s each, 9.5 s total; 1.7.0 grows a third at a time,
   and **zero** failed requests (out of 2400 in the video). Costs: a third less capacity during the rollout, and
   rollback is another 9 s rollout. Kubernetes does this for a Deployment (`maxUnavailable`, `maxSurge`, both 25% by
   default); this script is max unavailable 1, max surge 0.

   Graceful shutdown matters. A process that ignores SIGTERM (`sleep` as PID 1):
   ```bash
   docker run -d --name stubborn python:3.12.15-slim sleep infinity
   time docker stop -t 10 stubborn
   docker inspect -f '{{.State.ExitCode}}' stubborn
   docker rm stubborn
   ```
   `real 0m10.1s` and exit code `137`: killed after the full timeout. Course Copilot stops in under half a second with
   exit code 0. The scripts always pass `-t 10`, so the wait is the same everywhere.

4. **Strategy 2: blue-green.**
   ```bash
   bash users.sh bluegreen 70         # laptop
   ./bluegreen.sh 1.7.0               # prod-01
   ./switch.sh green                  # ~15 s later
   ./switch.sh blue                   # ~20 s later: the "rollback"
   ```
   ```
   ... green is up: 3 instances of 1.7.0
   ... smoke test green-1 /ask: 200
   ... green passed. users are still on blue. switch with: ./switch.sh green
   ... all traffic now goes to green (switch took 131 ms)
   ... all traffic now goes to blue (switch took 67 ms)
   ```
   Zero failures across both switches. The price: everything runs twice (six instances, about 34 MB each). And blue
   and green share the database: a version that renames a column breaks blue, and your rollback. Use expand
   (add the new column, keep the old), migrate (write both, backfill, switch reads), contract (drop the old one only
   when nothing needs it). Lesson 4 does this with real migrations.

5. **Strategy 3: canary, good release.** In the second prod-01 terminal start the watchdog first:
   ```bash
   bash users.sh canary 80            # laptop
   ./watchdog.sh                      # prod-01, terminal 2
   ./canary.sh 1.7.0 10               # prod-01, terminal 1
   cat /srv/lb/conf.d/route.conf
   ./canary.sh 1.7.0 50               # ~25 s later: green grows to 3 instances
   ./canary.sh 1.7.0 100              # ~20 s later
   ```
   route.conf uses `split_clients "${request_id}"`: `10% green; * blue;`. The watchdog reads the last 5 s of the LB
   log every second; green's error rate stays 0%. Zero failed (out of 3200 in the video). Stop the watchdog with
   Ctrl+C.

6. **Canary, bad release (1.7.1, staged).** First, a health check that lies:
   ```bash
   source lib.sh; start_app green-1 1.7.1; wait_ready green-1
   curl -s 10.0.93.21:8000/health; echo
   curl -s '10.0.93.21:8000/ask?q=docker'; echo
   docker logs green-1 2>&1 | grep Error | tail -1
   docker rm -f green-1; pool_clear green
   ```
   `{"status":"ok","version":"1.7.1",...}`, then `Internal Server Error` and `KeyError: 'level'`. Now the canary:
   ```bash
   bash users.sh canarybad 45         # laptop
   ./watchdog.sh                      # prod-01, terminal 2
   ./canary.sh 1.7.1 10               # prod-01, terminal 1
   ```
   ```
   ... green: 1 of 2 requests failed in the last 5s (50%)
   ... green: 4 of 7 requests failed in the last 5s (57%)
   ... green: 5 of 9 requests failed in the last 5s (55%)
   ... green: 8 of 12 requests failed in the last 5s (66%)
   ... error rate above 5%: ROLLBACK. all traffic back to blue
   ```
   About 4 s after the canary went live, everyone is back on blue: 9 failed requests, all inside the 10%. A canary
   checks whether a release is safe (minutes); an A/B test compares product ideas (days). Argo Rollouts automates
   canary steps in Kubernetes (Module 15).

7. **The pitfall: a rolling update without readiness.**
   ```bash
   bash users.sh naive 40             # laptop
   ./rolling-naive.sh 1.7.0           # prod-01
   ```
   Each instance is replaced before the previous one is up: a rolling update that turns into a recreate (174 failed
   requests in about 4 s in the video).

8. **Side by side** (the video's numbers):

   | Strategy | Failed requests | Rollback | Extra servers | Blast radius |
   |---|---|---|---|---|
   | Recreate | 182 in 4.5 s | another recreate (another outage) | none | everyone |
   | Rolling | 0 | another rollout, ~9 s | none (1/3 less capacity during it) | a growing share |
   | Blue-green | 0 | switch, 67 ms | double | everyone at once |
   | Canary | 0 good; 9 bad, auto-rollback in 4 s | automatic | a few | 10% first |

## Common mistakes
- **Rolling updates without readiness.** No drain and no ready check turns rolling into recreate.
- **Health checks that lie.** 1.7.1 said ok and failed every question. Smoke-test a real request; judge on metrics.
- **A canary without metrics.** Without the watchdog, 10% of users would keep getting errors: a slow big bang.
- **Sticky sessions.** Splitting on the request ID sends one user to both versions. Real canaries split by user
  (cookie or user ID).
- **Breaking database changes.** Renaming a column breaks the old version and your rollback. Expand, migrate, contract.

## Clean up
```bash
cd lab
bash down.sh
rm -rf runs
```

## Next
[M09-L03 · Feature Flags](../m09-l03-feature-flags/)
