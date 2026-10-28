# M17-B01 · Game Day with SLOs, Chaos and a Postmortem
> Video: Module 17, Build 1. Watch it first, then follow along here.

## What you'll learn
- Putting Module 17 together: SLOs and the error budget policy as code, a board and burn-rate pages, runbooks.
- Planning a game day: roles, rules of engagement, abort lines, and sealed hypotheses written before the day.
- Running real, unannounced failures (a bad release, a migration lock, a hung dependency) and measuring detection,
  response and the budget each one cost.
- Finding the shared root cause (slow dependencies eating the API's time) and fixing it with timeouts, circuit
  breakers and bulkheads, then re-running the same experiments until they hold.
- Writing the blameless postmortem and the game day report.

## Before you start
- Docker Desktop (Compose v2), `git`, `curl`, `jq`, `python3`, `bash`.
- Lessons [M17-L01](../m17-l01-slis-slos-and-error-budgets/) to [M17-L04](../m17-l04-chaos-engineering-and-disaster-recovery/).
- Free ports: 8080 (nginx), 8081 (lab pager), 8082 (lab status page), 3000 (Grafana), 9090 (Prometheus), 9093 (Alertmanager).
- Images used (pinned): `postgres:18.6-alpine3.24`, `python:3.13.16-slim`, `nginx:1.29.8-alpine`, `prom/prometheus:v3.15.0`,
  `prom/alertmanager:v0.34.1`, `grafana/grafana:13.2.4`, `ghcr.io/slok/sloth:v0.16.0`.
- A game day works best with two people: one game master (runs `gameday/gm.sh`, never helps) and one responder.
  Alone, you play both: open two terminals, and try not to read `gameday/sealed/` before each scenario.

## Files in this folder
| File | What it is |
|---|---|
| `lab/compose.yaml` | 11 containers: `db`, `api1` + `api2`, `copilot`, `lb` (nginx), `students` (20 req/s), Prometheus, Alertmanager, pager, status page, Grafana |
| `lab/app/` | catalog-api 1.0 (course list + Copilot answers, 8 worker threads). `setup-app-repo.sh` makes it a git repo with tags v1.0 and v1.1 |
| `lab/versions/` | `api-1.1.py` (the staged bad release), `api-1.2.py` (the fix: breakers, bulkheads, short timeouts), `nginx-1.2.conf` (the nginx fix) |
| `lab/copilot/copilot.py` | Course Copilot: a keyword service, no AI model |
| `lab/slo/slos.yml` | The three SLOs as a Sloth spec; `slo/sloth-rules.yml` is what Sloth generated |
| `lab/prometheus/slo-gameday.yml` | The lab rules: windows compressed (1 h -> 5 m, 5 m -> 1 m), budget used, the page and the stale ticket |
| `lab/alertmanager/alertmanager.yml` | Pages to the pager, tickets to the queue, grouped by alert and SLO |
| `lab/docs/error-budget-policy.md` | The policy, including: a game day may spend at most 10 % of any budget |
| `lab/runbooks/*.md` | One runbook behind every page |
| `lab/gameday/plan.md` | Goal, roles, rules of engagement, abort lines |
| `lab/gameday/gm.sh` | The game master's script (lesson 4's `chaos.sh`, grown up): steady state, inject, check abort lines every 10 s, roll back when the IC logs "mitigated" |
| `lab/gameday/sealed/` | The hypotheses and the three scenarios (`s1-bad-release`, `s2-db-lock`, `s3-copilot-hang`) |
| `lab/release.sh`, `lab/deploy.sh` | Build an image from a git tag; roll both replicas one at a time (also the rollback) |
| `lab/flag.sh` | Feature flags / kill switch (`./flag.sh ask off`) |
| `lab/probe.sh`, `lab/pq.sh`, `lab/alerts.sh` | Probe a URL from api1 (2 s limit), query Prometheus, list active alerts |
| `lab/inc.sh`, `lab/status.sh` | Incident notes and status page updates (lesson 2) |
| `lab/timeline.py` | `python3 timeline.py SCENARIO [N]`: the timeline and numbers of one scenario, from real logs only |
| `lab/gameday/report.md`, `lab/postmortem/2026-10-21-gameday-slow-dependencies.md` | The video's game day report and postmortem, as examples |
| `lab/grafana/` | Boards **allcsvideos · SLOs (game day)** and the review board with injections marked |

## Follow along
### Build steps
1. Make `app/` a git repo (tags v1.0 and v1.1), build both releases, start the lab.
   ```bash
   cd lab
   chmod a+w runs                 # the students container writes runs/students.csv
   ./setup-app-repo.sh
   ./release.sh 1.0
   ./release.sh 1.1
   docker compose up -d --wait
   docker compose ps --format "table {{.Service}}\t{{.Image}}\t{{.Status}}"
   ```
   You should see eleven containers, `api1` and `api2` on `gameday-lab/api:1.0`.

2. Step 1, SLOs as code. Generate the production rules with Sloth and check everything.
   ```bash
   docker run --rm -v "$PWD/slo:/slo" ghcr.io/slok/sloth:v0.16.0 --no-log generate -i /slo/slos.yml -o /slo/sloth-rules.yml && wc -l slo/sloth-rules.yml
   grep -c "record:" slo/sloth-rules.yml
   docker run --rm -v "$PWD:/w" --entrypoint promtool prom/prometheus:v3.15.0 check rules /w/slo/sloth-rules.yml /w/prometheus/slo-gameday.yml
   docker run --rm -v "$PWD/alertmanager:/a" --entrypoint amtool prom/alertmanager:v0.34.1 check-config /a/alertmanager.yml
   ```
   ```
   594 slo/sloth-rules.yml
   45
     SUCCESS: 51 rules found
     SUCCESS: 20 rules found
   Checking '/a/alertmanager.yml'  SUCCESS
   ```
   Read `docs/error-budget-policy.md`: at 20 requests/s the month's budgets are 46,656 failed course lists,
   466,560 slow ones and 51,840 failed questions.

3. Step 2, the board and the pages. Open Grafana at http://localhost:3000, dashboard **allcsvideos · SLOs (game day)**.
   The pager is at http://localhost:8081 and the status page at http://localhost:8082.

4. Steps 3 and 4: read `runbooks/*.md` and `gameday/plan.md`. Step 5: the steady load is already running. Try it:
   ```bash
   git -C app log --format="%h %d %s (%an)"
   curl -s localhost:8080/api/courses | jq -c .
   curl -s "localhost:8080/api/ask?q=kubernetes" | jq -c .
   ./probe.sh http://copilot:8000/healthz
   cat flags/flags.json
   ```
   ```
   {"served_by":"api2","version":"1.0","courses":["Linux Basics","Docker Deep Dive","Kubernetes in Production","System Design","Spring Boot"]}
   {"served_by":"api2","answer":"Try: Kubernetes in Production","courses":["Kubernetes in Production"],"model":"none (keyword match)"}
   200 0.006s
   ```

### The game day
5. Steady state:
   ```bash
   ./pq.sh 'slo:sli_error:ratio_rate5m'
   ./pq.sh 'slo:budget_used:ratio_gameday'
   ```
   All three SLOs at 0.

6. **Scenario 1.** Game master terminal:
   ```bash
   ./gameday/gm.sh s1-bad-release
   ```
   It prints the steady state, the hypothesis, then a line every 10 seconds (course list errors climb to about 10 %).
   Responder terminal: wait for the page, then run the lesson 2 process. Use the page number the pager shows.
   ```bash
   tail -3 incident/pager.log | jq -c '{ts, event, who, summary}'
   curl -s -X POST 'localhost:8081/ack?page=1&who=asha' | jq -c .
   ./inc.sh asha "SEV2 declared: course list failing for many students. IC asha, ops priya, comms and scribe meera"
   ./status.sh investigating "Course catalog" partial "We are investigating errors when loading the course list. Next update in 15 minutes."
   ./pq.sh 'sum by (route, code) (rate(http_requests_total{job="students"}[1m])) > 0'
   tail -2 incident/deploys.log | jq -c "{at: (.epoch | strflocaltime(\"%H:%M:%S\")), version, by}"
   ```
   ```
   code=500 route=/api/courses   1.5454
   {"at":"23:28:31","version":"1.1","by":"ci"}
   ```
   A deploy in the last hour: roll back first. Then confirm, and log "mitigated" (that word tells `gm.sh` to stop).
   ```bash
   ./inc.sh priya "Errors started with catalog-api 1.1 from ci. Runbook: a deploy in the last hour, roll back first. Rolling back to 1.0."
   ./inc.sh asha "Approved."
   ./deploy.sh 1.0 priya
   ./pq.sh 'slo:sli_error:ratio_rate1m{slo="catalog-availability"}'
   ./inc.sh asha "Mitigated: course list errors back to 0 after the rollback to 1.0"
   ./status.sh monitoring "Course catalog" operational "We rolled back a change that caused the errors. The course list is loading again. We are monitoring."
   ```
   When the page resolves:
   ```bash
   ./status.sh resolved "Course catalog" operational "This incident has been resolved."
   ./inc.sh asha "Resolved. Postmortem owner: priya."
   python3 timeline.py s1-bad-release
   ```
   ```
   time to detect (fault -> first page):    1 min 39 s
   time to acknowledge (page -> ack):       0 min 22 s
   time to mitigate (fault -> 'mitigated'): 3 min 18 s
   catalog-availability    277 bad of  9000, for 2 min 35 s: 0.59% of the 30-day budget
   ```
   Hypothesis 1 held.

7. **Scenario 2**, five quiet minutes later. Game master:
   ```bash
   ./gameday/gm.sh s2-db-lock
   ```
   Responder: a ticket (`CatalogServingStale`) arrives first, then a page. Triage from the board, not from the
   alert's text. Look at the codes, the workers, the stale answers, then the locks on `courses`:
   ```bash
   tail -4 incident/pager.log | jq -c '{ts, event, alert, summary}'
   ./pq.sh 'sum by (route, code) (rate(http_requests_total{job="students"}[1m])) > 0'
   ./pq.sh 'api_workers_busy'
   ./pq.sh 'sum(rate(api_stale_answers_total[1m]))'
   docker compose exec -T db psql -U allcs -d catalog -c "SELECT l.pid, a.application_name AS app, l.mode, l.granted, date_trunc('second', now() - a.xact_start) AS held_for FROM pg_locks l JOIN pg_stat_activity a USING (pid) WHERE l.relation = 'courses'::regclass AND l.mode = 'AccessExclusiveLock'"
   ```
   ```
    pid  |    app     |        mode         | granted | held_for
   ------+------------+---------------------+---------+----------
    2282 | migrate-42 | AccessExclusiveLock | t       | 00:01:44
   ```
   End it (use your pid), then log it:
   ```bash
   ./inc.sh priya "migrate-42 holds an AccessExclusiveLock on courses. Propose: end it, re-run later with a lock_timeout."
   ./inc.sh asha "Approved."
   docker compose exec -T db psql -U allcs -d catalog -c 'SELECT pg_terminate_backend(<PID>)'
   ./inc.sh asha "Mitigated: migration ended, the course list reads the database again"
   ./inc.sh asha "Resolved."
   python3 timeline.py s2-db-lock
   ```
   In the video: 799 failed course lists (1.71 % of the budget), 894 slow ones, 81 failed questions. Hypothesis 2 failed.

8. **Scenario 3.** Game master:
   ```bash
   ./gameday/gm.sh s3-copilot-hang
   ```
   Responder: acknowledge, declare, diagnose:
   ```bash
   ./pq.sh 'sum by (route, code) (rate(http_requests_total{job="students"}[1m])) > 0'
   ./pq.sh 'api_workers_busy'
   ./pq.sh 'sum by (result) (rate(api_copilot_calls_total[1m]))'
   ./probe.sh http://copilot:8000/healthz
   ```
   ```
   code=502 route=/api/courses   18.0013
   code=502 route=/api/ask   2.0001
   instance=api1:9100 job=api   1
   instance=api2:9100 job=api   2
   FAILED URLError <urlopen error timed out> after 2.072s
   ```
   The runbook's action: the kill switch.
   ```bash
   ./flag.sh ask off
   ./inc.sh asha "Mitigated: course list healthy with Copilot switched off. Waiting for the Copilot team."
   ```
   After the game master removes the fault:
   ```bash
   ./probe.sh http://copilot:8000/healthz
   ./flag.sh ask on
   python3 timeline.py s3-copilot-hang
   ```
   In the video: 2,511 failed course lists in 2 min 21 s, 5.38 % of the budget, and an unacknowledged second page
   escalated to Priya. Hypothesis 3 failed badly.

### Review and fix
9. Ask nginx why. Use the start and end times of your scenario 3 (here IST, `+05:30`):
   ```bash
   docker compose logs lb --since 2026-10-21T23:45:05+05:30 --until 2026-10-21T23:48:16+05:30 2>&1 | grep -oE "(no live upstreams|upstream timed out|connect\(\) failed)[^,]*" | sort | uniq -c
   ```
   ```
      2797 no live upstreams while connecting to upstream
        56 upstream timed out (110: Operation timed out) while reading response header from upstream
   ```
   `max_fails=1` plus `proxy_next_upstream timeout`: two hung questions a second kept both replicas marked dead.

10. The fix, as code: revert 1.1, commit 1.2, tag it.
    ```bash
    git -C app revert --no-edit v1.1
    cp versions/api-1.2.py app/api.py
    git -C app commit -am "catalog-api 1.2: a circuit breaker and a bulkhead for each dependency, short timeouts (game day findings)"
    git -C app tag v1.2
    git -C app diff --stat v1.0 v1.2
    ```
    ```
     api.py | 62 +++++++++++++++++++++++++++++++++++++++++++++++++++++++-------
     1 file changed, 55 insertions(+), 7 deletions(-)
    ```
    And nginx: questions get their own location with `proxy_next_upstream error` only.
    ```bash
    cp versions/nginx-1.2.conf nginx/nginx.conf
    docker compose exec lb nginx -t -c /etc/nginx/lab/nginx.conf
    docker compose exec lb nginx -s reload
    ./release.sh 1.2
    ./deploy.sh 1.2 priya
    ./pq.sh 'api_breaker_open'
    ```

11. Re-run the same sealed scenarios with the same hypotheses:
    ```bash
    ./gameday/gm.sh s2-db-lock        # course list errors 0, slow 0, the whole time; only the ticket
    ./gameday/gm.sh s3-copilot-hang   # only copilot-availability pages; the course list stays at 0
    ```
    Respond as before (for scenario 3 this time: SEV3, Copilot failing, course list healthy). Then:
    ```bash
    ./pq.sh 'sum by (result) (rate(api_copilot_calls_total[1m]))'
    python3 timeline.py s3-copilot-hang -1
    ```
    ```
    result=breaker_open   1.8364
    catalog-availability      0 bad of  4723: 0.00% of the 30-day budget
    copilot-availability    373 bad of   525, for 3 min 06 s: 0.72% of the 30-day budget
    ```

12. What did the whole game day cost?
    ```bash
    ./pq.sh 'slo:budget_used:ratio_gameday'
    ```
    In the video 7.70 % of the course-list budget, under the 10 % cap. Compare your numbers with `gameday/report.md`,
    then write your postmortem like `postmortem/2026-10-21-gameday-slow-dependencies.md`: summary, impact from
    `timeline.py`, timeline, contributing factors (how, not who), what went well, owned action items.

## Common mistakes
- **Triage from an alert's text.** The stale-copy ticket said "students see no errors" while the board showed 10 %.
  Read the SLIs first.
- **A story that fits the pressure, not the numbers.** The note blamed the API's workers; the metrics showed 1 and 2 busy.
- **Nobody on the second page.** Everyone was on the first one, so the Copilot page escalated.
- **Failing fast isn't enough** while every request still waits for a shared resource in turn: add bulkheads.
- **Starting in production.** Run game days in staging first, with abort lines and one person who can stop it.

## Clean up
```bash
docker compose down -v
docker image rm gameday-lab/api:1.0 gameday-lab/api:1.1 gameday-lab/api:1.2
rm -f incident/*.log runs/students.csv gameday/gm.log gameday/STOP
```
To start over from 1.0, also `rm -rf app/.git` and restore `app/api.py` and `nginx/nginx.conf` from the course repo
(for example `git checkout -- app/api.py nginx/nginx.conf` from inside your clone).

## Next
[M18-L01 · Shift Left](../../security/m18-l01-shift-left/)
