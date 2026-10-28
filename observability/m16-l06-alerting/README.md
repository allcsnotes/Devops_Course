# M16-L06 · Alerting
> Video: Module 16, Lesson 6. Watch it first, then follow along here.

## What you'll learn
- What deserves a page: urgent, actionable, real - symptoms users feel, not causes like CPU.
- How an alert travels: Prometheus rules (inactive -> pending -> firing) -> Alertmanager (dedup, group, route, inhibit, silence) -> receivers.
- Writing alert rules with `for`, `keep_firing_for`, severity labels and a runbook link; a Watchdog heartbeat.
- Alertmanager routing trees, timers (`group_wait`, `group_interval`, `repeat_interval`), inhibition and silences with `amtool`.
- Testing rules with `promtool test rules`, and checking configs before loading them.
- How 31 pages became 3 for the same incident.

## Before you start
- Docker Desktop (Compose v2), `curl`, `jq`, a browser. Two terminals.
- [M16-L01](../m16-l01-the-three-pillars-and-what-to-measure/) (the staged migration lock) and [M16-L02](../m16-l02-metrics-with-prometheus/) (PromQL, recording rules).

## Files in this folder
| File | What it is |
|---|---|
| `lab/compose.yaml` | Project `m16-alerting`: `db`, `api` (port 8080), `load` (10 req/s), Prometheus v3.15.0 (9090), Alertmanager v0.34.1 (9093), `receiver`. `PROM_CONFIG` / `AM_CONFIG` pick the config files |
| `lab/api/`, `lab/db/init.sql`, `lab/load/traffic.py` | The lab API from M16-L01 (shared `http_*` metrics, pool of 4), its database, the students |
| `lab/db/migration.sql` | The staged lock: `ALTER TABLE` + `pg_sleep(180)`, then `ROLLBACK` so every run starts the same |
| `lab/prometheus/prometheus-naive.yml`, `alerts-naive.yml` | The first attempt: five alerts, no `for`, causes and symptoms mixed |
| `lab/alertmanager/alertmanager-naive.yml` | The first attempt: no grouping (`'...'`), everything to the pager, repeat every minute |
| `lab/prometheus/prometheus.yml`, `rules.yml`, `alerts.yml` | 4 recording rules; 5 alerts: `ApiHighErrorRate`, `ApiHighLatencyP99` (page), `DbPoolSaturated` (ticket), `ApiCpuHigh` (cause, for comparison), `Watchdog` |
| `lab/alertmanager/alertmanager.yml` | Routing tree (heartbeat, pager, tickets, default chat), timers, one inhibit rule, 4 webhook receivers |
| `lab/prometheus/tests-wrong.yml`, `tests.yml` | Rule unit tests: the staged wrong expectation, and the fixed one |
| `lab/receiver/receiver.py` | Stand-in for pager / tickets / chat: logs one line per notification, appends the JSON to `runs/<path>.jsonl` |
| `lab/tools.sh` | `pq`, `promtool` and `amtool` helpers (the tools run inside their containers) |

## Follow along

1. The first attempt - start the lab with the naive configs:
   ```bash
   mkdir -p ~/m16-alerting && cp -R lab/. ~/m16-alerting/ && cd ~/m16-alerting
   PROM_CONFIG=prometheus-naive.yml AM_CONFIG=alertmanager-naive.yml docker compose up -d --build
   source tools.sh
   ```
   Let it run for 2-3 minutes. Even before anything breaks, a single slow scrape can page (`SlowRequests` - no `for`).

2. Stage the incident: the migration holds its lock for 3 minutes (the command returns when it is done):
   ```bash
   docker compose exec -T db psql -U postgres -d catalog -q < db/migration.sql
   sleep 60
   docker compose logs --no-log-prefix load | tail -25
   docker compose logs --no-log-prefix receiver
   ```
   ```
   20:45:25 req=97 ok=0 err=97
   ...
   20:45:31 pager     FIRING   alerts=1 firing=1 RequestsWaiting
   20:45:31 pager     FIRING   alerts=1 firing=1 PoolBusy
   20:45:46 pager     FIRING   alerts=1 firing=1 ServerErrors
   ...
   ```
   One notification per alert, again and again (31 in 6 minutes in the video), and none says what to do.

3. Switch to the real configs (and clear the receiver's files):
   ```bash
   rm -f runs/*.jsonl
   docker compose up -d --force-recreate prometheus alertmanager receiver
   docker compose ps --format "table {{.Service}}\t{{.Image}}\t{{.Status}}"
   ```

4. The metrics and the recording rules:
   ```bash
   curl -s localhost:8080/metrics | grep -E '^(http_requests_in_flight|db_pool_(in_use|size)) '
   sleep 60
   pq 'job_route:http_errors:ratio_rate1m'
   pq 'job:http_request_duration_seconds:p99_1m'
   pq 'job:db_pool:saturation'
   ```
   Error ratio `0` on both routes, p99 ~5 ms, pool saturation `0`. Read `prometheus/alerts.yml` and
   `alertmanager/alertmanager.yml` now - the video walks through every line.

5. Check before loading, then ask the routing tree:
   ```bash
   promtool check rules rules.yml alerts.yml
   amtool check-config alertmanager.yml
   amtool config routes
   amtool config routes test severity=page job=api
   amtool config routes test severity=ticket job=api
   amtool config routes test alertname=DiskFilling job=db
   amtool config routes test --verify.receivers=pager severity=ticket job=api; echo "exit code $?"
   ```
   ```
     SUCCESS: 4 rules found
     SUCCESS: 5 rules found
   ...
    - 1 inhibit rules
    - 4 receivers
   └── default-route  receiver: chat
       ├── {alertname="Watchdog"}  receiver: heartbeat
       ├── {severity="page"}  receiver: pager
       └── {severity="ticket"}  receiver: tickets
   pager
   tickets
   chat
   WARNING: Expected receivers did not match resolved receivers.
   exit code 1
   ```
   (Inside the helper, `exit code` reflects the container's amtool exit status.)

6. The same incident, with good rules. In the second terminal run the migration; in the first, watch
   http://localhost:9090/alerts (pending after ~30 s, firing a minute later) and http://localhost:9093:
   ```bash
   docker compose exec -T db psql -U postgres -d catalog -q < db/migration.sql      # second terminal
   ```
   After it finishes and a few more minutes pass:
   ```bash
   docker compose logs --no-log-prefix receiver
   ```
   ```
   20:51:38 heartbeat FIRING   alerts=1 firing=1 Watchdog
   20:55:24 pager     FIRING   alerts=3 firing=3 ApiHighErrorRate,ApiHighLatencyP99
   20:58:24 pager     FIRING   alerts=3 firing=2 ApiHighErrorRate,ApiHighLatencyP99
   20:59:24 pager     RESOLVED alerts=3 firing=0 ApiHighErrorRate,ApiHighLatencyP99
   ```
   One page per service, with an update and a resolve. `ApiCpuHigh` never fired (CPU stayed low); `DbPoolSaturated`
   was shown as **Inhibited** in Alertmanager's UI - no ticket was sent.

7. What the pager received, and the deduplication counters:
   ```bash
   jq '{receiver, status, groupLabels, commonLabels, alerts: [.alerts[] | {status, route: .labels.route, alertname: .labels.alertname, summary: .annotations.summary}]}' <(head -1 runs/pager.jsonl)
   curl -s localhost:9090/metrics | grep -E '^prometheus_notifications_sent_total'
   curl -s localhost:9093/metrics | grep -E '^alertmanager_(alerts_received_total|notifications_total)' | grep -v ' 0$'
   ```
   ```
   "summary": "/api/courses: 100% of requests fail"
   prometheus_notifications_sent_total{...} 30
   alertmanager_alerts_received_total{status="firing",...} 19
   alertmanager_alerts_received_total{status="resolved",...} 11
   alertmanager_notifications_total{integration="webhook"} 8
   ```

8. Planned work: silence it first, then expire the silence when done.
   ```bash
   amtool silence add job=api --duration=15m --author=asha --comment="planned migration: add courses.level"
   amtool silence query
   docker compose exec -T db psql -U postgres -d catalog -q < db/migration.sql      # second terminal
   amtool alert query
   amtool alert query --silenced
   docker compose logs --no-log-prefix --since 7m receiver
   amtool silence expire $(amtool silence query -q)
   amtool silence query --expired
   ```
   During the lock `amtool alert query` shows only `Watchdog`; `--silenced` shows the page alerts as `suppressed`;
   the receiver gets heartbeats only. (amtool prints times in UTC.)

9. Test the rules. First the staged wrong expectation (a page 30 s after errors start):
   ```bash
   promtool test rules tests-wrong.yml
   promtool test rules tests.yml
   ```
   ```
     FAILED:
       alertname: ApiHighErrorRate, time: 2m30s,
           exp:[ ... ], got:[]
     SUCCESS
   ```
   At 2m30s the alert is only pending - `for: 1m` is doing its job.

## Common mistakes
- Rules with no `for`: one slow scrape pages someone, then resolves itself.
- Alerting on causes (CPU, memory, pool size per instance): they fire when nothing is wrong and stay quiet during real outages (CPU was ~3% during this one).
- No grouping (`group_by: ['...']`): 8 alerts became 31 pages. Group by service.
- Absent data: if the API stops being scraped, its error ratio has no series and can't fire. Alert on `up == 0` or `absent(...)`, and keep a Watchdog.
- Forgotten silences: keep them short, with an author and a reason; expire them when the work is done.
- Pages without a runbook, and pages nobody acts on: review every page after each on-call week.

## Clean up
```bash
cd ~/m16-alerting
docker compose down -v --rmi local
cd ~ && rm -rf ~/m16-alerting
```

## Next
[M16-B01 · Full Observability for allcsvideos](../m16-b01-full-observability-for-allcsvideos/) - metrics, logs and traces in one Grafana, with alerts that page on real problems.
