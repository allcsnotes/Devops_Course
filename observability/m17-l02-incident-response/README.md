# M17-L02 · Incident Response
> Video: Module 17, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- On-call: rotations, primary and secondary, escalation, handoffs, and keeping the load humane.
- Severity levels tied to the SLO, and declaring an incident early.
- Incident roles: incident commander (IC), operations lead, communications lead, scribe; and the IC's loop.
- The five stages (detect, triage, mitigate, resolve, learn) and MTTD / MTTA / MTTR, measured from a real timeline.
- Writing a blameless postmortem with contributing factors and owned action items.

## Before you start
- Docker Desktop (Compose v2), `curl`, `jq`, `python3`.
- Lesson [M17-L01](../m17-l01-slis-slos-and-error-budgets/) (SLOs and burn-rate alerts) and Module 16
  (Prometheus, Loki, Tempo, Alertmanager routing).
- Free ports: 8080 (API), 8081 (lab pager), 8082 (lab status page), 3000 (Grafana), 9090 (Prometheus),
  9093 (Alertmanager), 3100 (Loki), 3200 (Tempo).
- Images used (pinned): `python:3.13.16-slim`, `postgres:18.6-alpine3.24`, `prom/prometheus:v3.15.0`,
  `prom/alertmanager:v0.34.1`, `grafana/loki:3.7.9`, `grafana/alloy:v1.21.0`, `grafana/tempo:3.1.0`, `grafana/grafana:13.2.4`.

## Files in this folder
| File | What it is |
|---|---|
| `lab/compose.yaml` | Catalog API + PostgreSQL (2 million fake enrollments), Prometheus, Alertmanager, lab pager, lab status page, Loki + Alloy, Tempo, Grafana, and a `load` profile |
| `lab/app/` | The catalog API. Release 1.5.0 adds a "trending this week" count whose query (on purpose) reads every enrollment |
| `lab/prometheus/rules.yml` | SLO 99.5 %: fast-burn page (14.4x on 5m and 1m windows, shortened for the lab) and a p95 latency ticket |
| `lab/alertmanager/alertmanager.yml` | `severity=page` goes to the pager, everything else to the ticket queue |
| `lab/pager/pager.py` | Lab stand-in for PagerDuty/Opsgenie: pages Asha, escalates to Rahul after 120 s without an ack. No real calls |
| `lab/status/status.py` | Lab status page |
| `lab/load/traffic.py` | Simulated students, 10 requests/s, each request saved to `runs/RUN.csv` |
| `lab/deploy.sh` | `./deploy.sh VERSION WHO`: roll the API to a version (also the rollback), log it, mark it in Grafana |
| `lab/inc.sh` | `./inc.sh WHO "note"`: one timestamped line in the incident log (the scribe's tool) |
| `lab/status.sh` | `./status.sh STATUS COMPONENT STATE "message"`: post a status page update |
| `lab/archive.sh` | `./archive.sh RUN`: move this run's logs to `runs/RUN-*.log` and reset pager and status page |
| `lab/timeline.py` | `python3 timeline.py RUN`: merges every source into the timeline and computes the response metrics |
| `postmortem-example-catalog-1.5.0.md` | The blameless postmortem written from the video's run |

## Follow along
1. Build both releases of the API, then start the lab (ten containers).
   ```bash
   cd lab
   docker build --build-arg APP_VERSION=1.4.2 -t catalog-api:1.4.2 app
   docker build --build-arg APP_VERSION=1.5.0 -t catalog-api:1.5.0 app
   docker compose up -d --wait
   docker compose ps --format "table {{.Service}}\t{{.Image}}\t{{.Status}}"
   ```
   The first start loads 2 million rows into PostgreSQL, so give it a minute. Open the pager at http://localhost:8081,
   the status page at http://localhost:8082 and Grafana at http://localhost:3000.

2. **Part A, without a process (the video's hook, optional).** Start the students, ship 1.5.0, and don't acknowledge
   the page. After 120 s it escalates from Asha to Rahul.
   ```bash
   RUN=r1 docker compose --profile load up -d load
   ./deploy.sh 1.5.0 priya
   curl -s localhost:8081/api/pages | jq .
   curl -s -X POST "localhost:8081/ack?page=1&who=rahul" | jq -c .
   ```
   Now three people restart things at once, nobody in charge:
   ```bash
   (docker compose restart api & docker compose restart db & docker compose restart api & wait)
   docker compose logs load --since 50s | tail -4
   ```
   Nothing changes:
   ```
   load-1  | 21:07:24 last 10s: 99 requests, 74 failed (75%)
   load-1  | 21:07:34 last 10s: 103 requests, 74 failed (72%)
   ```
   The status page still says all systems operational. Wait a few minutes (in the video the late rollback came at
   7 minutes), then roll back, stop the load and archive the run:
   ```bash
   ./deploy.sh 1.4.2 priya
   docker compose --profile load stop load
   ./archive.sh r1
   ```

3. **Part B, with a process.** Start the students and wait a minute, then Priya deploys 1.5.0.
   ```bash
   RUN=r2 docker compose --profile load up -d load
   ./deploy.sh 1.5.0 priya
   ```
   ```
   21:17:59 deploy catalog-api 1.5.0 by priya: start
   21:18:06 deploy catalog-api 1.5.0 by priya: done, {"ok":true,"version":"1.5.0"}
   ```

4. Detect. Wait for the page (about 80 seconds).
   ```bash
   tail -2 incident/pager.log | jq -c "{ts, event, who, alert, summary}"
   ```
   ```
   {"ts":"21:19:23","event":"triggered","who":null,"alert":"CatalogErrorBudgetBurn","summary":"catalog-api: 35.85% of requests failing (SLO 99.5%)"}
   {"ts":"21:19:23","event":"notified","who":"asha","alert":null,"summary":null}
   ```

5. Acknowledge, triage, declare SEV2 with roles, and post the first status update before you know the cause.
   ```bash
   curl -s -X POST "localhost:8081/ack?page=1&who=asha" | jq -c .
   ./inc.sh asha "SEV2 declared: course list failing for most users. IC asha, ops lead rahul, comms priya"
   ./status.sh investigating "Course catalog" partial "We are investigating errors when loading the course list. Video playback and checkout are working normally. Next update in 15 minutes."
   ```

6. The ops lead looks at metrics: which route fails, which release is running, when it was deployed.
   ```bash
   curl -sG localhost:9090/api/v1/query --data-urlencode "query=sum by (route) (rate(http_requests_total{status=~\"5..\"}[1m])) / sum by (route) (rate(http_requests_total[1m]))" | jq -r ".data.result[] | \"\(.metric.route)  \(.value[1][0:6])\""
   curl -sG localhost:9090/api/v1/query --data-urlencode "query=app_build_info" | jq -r ".data.result[].metric.version"
   tail -1 incident/deploys.log | jq -c "{start: (.start | strflocaltime(\"%H:%M:%S\")), version, by}"
   ```
   ```
   /api/courses  0.9102
   1.5.0
   {"start":"21:17:59","version":"1.5.0","by":"priya"}
   ```

7. Logs from Loki, then one failing trace from Tempo.
   ```bash
   curl -sG localhost:3100/loki/api/v1/query --data-urlencode "query=sum by (version) (count_over_time({service=\"api\", level=\"error\"}[5m]))" | jq -r ".data.result[] | \"version \(.metric.version): \(.value[1]) error lines\""
   curl -sG localhost:3100/loki/api/v1/query_range --data-urlencode "query={service=\"api\", level=\"error\"}" --data-urlencode limit=1 | jq -r ".data.result[0].values[0][1]" | jq -c "{ts, version, route, status, duration_ms, error, trace_id}"
   id=$(curl -sG localhost:3200/api/search --data-urlencode "q={ status = error }" --data-urlencode limit=1 | jq -r ".traces[0].traceID"); echo "trace $id"
   curl -s localhost:3200/api/v2/traces/$id | jq -r ".trace.resourceSpans[].scopeSpans[].spans[] | \"\(.name[0:60])  \(((.endTimeUnixNano|tonumber) - (.startTimeUnixNano|tonumber)) / 1e6 | floor) ms  \(.status.code // \"\")\""
   ```
   ```
   version 1.5.0: 836 error lines
   {"ts":"...","version":"1.5.0","route":"/api/courses","status":500,"duration_ms":1114.4,"error":"QueryCanceled: canceling statement due to statement timeout",...}
   GET /api/courses  1220 ms  STATUS_CODE_ERROR
   SELECT  3 ms
   SELECT  1093 ms  STATUS_CODE_ERROR
   ```

8. Mitigate: write it down, the IC approves, roll back first and fix forward later.
   ```bash
   ./inc.sh rahul "Errors began with the 1.5.0 deploy. /api/courses hits the 1 s statement timeout on the new trending query. Propose rollback to 1.4.2."
   ./inc.sh asha "Approved: roll back to 1.4.2 now. Fix forward later."
   ./deploy.sh 1.4.2 rahul
   ```

9. Confirm recovery from the users' side, then update the status page.
   ```bash
   curl -sG localhost:9090/api/v1/query --data-urlencode "query=service:http_errors:ratio_rate1m" | jq -r ".data.result[] | \"error ratio (1m): \(.value[1])\""
   docker compose logs load --since 25s | tail -2
   ./inc.sh rahul "Error ratio back to 0 since the rollback. Course list loads."
   ./status.sh monitoring "Course catalog" operational "We rolled back a change that caused the errors. The course list is loading again. We are monitoring."
   ```
   The 1-minute ratio still shows about 0.19 (its window still holds the bad minute), but the students see 0 failed.

10. Resolve. When the alert resolves by itself, close the incident and name the postmortem owner.
    ```bash
    tail -1 incident/pager.log | jq -c "{ts, event, alert, ends_at}"
    ./status.sh resolved "Course catalog" operational "This incident has been resolved. The course list is loading normally for everyone. We will publish what happened and what we are changing."
    ./inc.sh asha "Resolved. Postmortem owner: rahul. Review on Friday."
    docker compose --profile load stop load
    ./archive.sh r2
    ```

11. Build the timeline from every source and read the response metrics.
    ```bash
    python3 timeline.py r2
    ```
    ```
    timeline of r2 (T = first failed request, 21:18:00 IST)
    21:17:59  T-00:02  deploy  catalog-api 1.5.0 rollout started (priya)
    21:18:00  T+00:00  users   first failed request (impact starts)
    21:19:23  T+01:23  pager   page #1 CatalogErrorBudgetBurn
    21:19:50  T+01:50  pager   acknowledged by asha
    21:19:57  T+01:56  asha    SEV2 declared: ...
    21:20:13  T+02:12  deploy  rollback to 1.4.2 started (rahul)
    21:20:15  T+02:15  users   last failed request (impact ends)
    ...
    time to detect (first failure -> page):       1 min 23 s
    time to acknowledge (page -> ack):            0 min 27 s
    time to restore (first -> last failure):      2 min 15 s
    requests during impact: 1355, failed: 890 (65.7%)
    ```
    Run `python3 timeline.py r1` too, if you did Part A: in the video it took 7 min 16 s to restore.

12. Learn. Find the cause for the postmortem with `EXPLAIN ANALYZE`, add the missing index, and ship 1.5.0 again.
    ```bash
    docker compose exec -T db psql -U postgres -d catalog -c "EXPLAIN (ANALYZE, COSTS OFF) SELECT course_id, count(*) FROM enrollments WHERE enrolled_at > now() - interval '7 days' GROUP BY course_id" | grep -E 'Scan|Filter|Rows Removed|Execution'
    docker compose exec -T db psql -U postgres -d catalog -c 'CREATE INDEX CONCURRENTLY enrollments_enrolled_at ON enrollments (enrolled_at)'
    docker compose exec -T db psql -U postgres -d catalog -c "EXPLAIN (ANALYZE, COSTS OFF) SELECT course_id, count(*) FROM enrollments WHERE enrolled_at > now() - interval '7 days' GROUP BY course_id" | grep -E 'Scan|Cond|Execution'
    ```
    Before: `Parallel Seq Scan`, `Rows Removed by Filter: 655064`, about 329 ms. After: `Bitmap Index Scan on
    enrollments_enrolled_at`, about 27 ms.
    ```bash
    RUN=r3 docker compose --profile load up -d load
    ./deploy.sh 1.5.0 rahul
    docker compose logs load --since 90s | tail -9
    curl -s localhost:8081/api/pages | jq length
    ```
    The fixed release serves the students, and no page fires (`0`).

13. Read `../postmortem-example-catalog-1.5.0.md` and write your own from your timeline: summary, impact with
    numbers, timeline, contributing factors (not a culprit), what went well, and action items with type, owner and date.

## Common mistakes
- **Everyone in the chat, nobody in charge.** Three restarts in the same second changed nothing. Name an IC first.
- **Debugging before mitigating.** If a change went out just before, roll it back first; find the root cause later.
- **Silence.** Post a status update early, even when you only know there's a problem, and promise the next one.
- **Trusting the health check.** `/healthz` answered ok from the broken release: it proves the process is up, not
  that users are served.
- **Postmortems that blame someone,** or action items with no owner and no date.
- **A crushing on-call.** Too few people, too many pages. Count pages per shift and act on the number.

## Clean up
```bash
docker compose --profile load down -v
docker image rm catalog-api:1.4.2 catalog-api:1.5.0
rm -f incident/*.log runs/*.csv runs/*.log
```

## Next
[M17-L03 · Load Testing and Capacity Planning](../m17-l03-load-testing-and-capacity-planning/)
