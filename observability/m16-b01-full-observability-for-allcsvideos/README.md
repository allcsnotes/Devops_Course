# M16-B01 · Full Observability for allcsvideos
> Video: Module 16, Build 1. Watch it first, then follow along here.

## What you'll learn
- Wiring all three signals for every service, tied together by one trace ID: metrics (with exemplars), JSON logs, OpenTelemetry traces.
- One Grafana with Prometheus, Loki and Tempo linked both ways: metric -> trace, log -> trace, trace -> logs, trace -> metrics.
- One overview dashboard kept as code: RED for every service, USE for the database and the host, deploy annotations.
- Symptom-only paging, grouped by team, with rules and routes checked in CI (`promtool`, `amtool`).
- The on-call path on a staged bad deploy: page -> board -> exemplar -> trace -> log line -> rollback.

## Before you start
- Docker Desktop (Compose v2), `curl`, `jq`, a browser. About 1 GB free memory for the stack (every container has a memory limit; ~690 MB in use in the video).
- All of Module 16: [L02](../m16-l02-metrics-with-prometheus/) Prometheus, [L03](../m16-l03-dashboards-with-grafana/) Grafana, [L04](../m16-l04-logs/) Loki/Alloy, [L05](../m16-l05-distributed-tracing/) tracing, [L06](../m16-l06-alerting/) alerting.

## Files in this folder
| File | What it is |
|---|---|
| `lab/compose.yaml` | Project `m16-full`, 12 containers + `load` (profile). Ports on localhost: Grafana 3000, Prometheus 9090, Alertmanager 9093, api 8080, copilot 8000, Loki 3100, Tempo 3200 |
| `lab/api/`, `lab/copilot/` | Lab builds (Flask API, FastAPI Copilot): shared `http_*` metrics with trace-ID exemplars, JSON logs with `trace_id`/`span_id`, started with `opentelemetry-instrument`. Copilot 1.1 = `SEARCH_TRANSCRIPTS=1` (the staged slow query) |
| `lab/db/init.sql` | Catalog database with 600,000 fake lesson transcripts; read-only `app` user (fake lab password) |
| `lab/alloy/config.alloy` | Postgres exporter -> Prometheus (remote write, job `postgres`, instance `catalog-db`); Docker logs of `api`/`copilot` -> Loki (`level` label, `trace_id` structured metadata) |
| `lab/otelcol/config.yaml`, `lab/tempo/tempo.yaml`, `lab/loki/loki.yaml` | Traces: OTLP -> memory_limiter, batch -> Tempo; Loki with 7-day retention |
| `lab/prometheus/prometheus.yml` | Scrapes api, copilot, node, otelcol, alertmanager; exemplar storage + remote-write receiver flags in compose |
| `lab/prometheus/rules.yml`, `alerts.yml`, `tests.yml` | Recording rules by job; pages: `HighErrorRate`, `HighLatencyP99`, `TargetDown`; ticket: `DbPoolSaturated`; Watchdog; unit tests |
| `lab/alertmanager/alertmanager.yml` | Pages grouped by `team`, 30 s group_wait; tickets inhibited while the team is paged |
| `lab/grafana/provisioning/datasources/datasources.yaml` | Prometheus (`prom`), Loki (`loki`), Tempo (`tempo`) with all the cross-links |
| `lab/grafana/dashboards/overview.json` | The overview board (uid `allcs-overview`) |
| `lab/receiver/receiver.py`, `lab/load/traffic.py` | Lab pager (webhook -> log line + `runs/*.jsonl`); students (6 course lists + 2 questions/s) |
| `lab/deploy.sh` | `deploy.sh copilot VERSION`: roll Copilot and post a deploy annotation |
| `lab/ci.sh` | `promtool check config` (+ both rule files), `promtool test rules`, `amtool check-config`, a routes test - using the pinned images |

## Follow along

1. Steps 1-7 are already written in the files; read them in the video's order: `api/app.py` (metrics, exemplars,
   log function) and `api/Dockerfile` (`opentelemetry-instrument`), the shared `x-otel` block in `compose.yaml`,
   `prometheus/prometheus.yml`, `alloy/config.alloy`, `otelcol/config.yaml`, `grafana/provisioning/datasources/datasources.yaml`,
   `grafana/dashboards/overview.json`, `prometheus/rules.yml` + `alerts.yml`, `alertmanager/alertmanager.yml`.

2. Run the CI checks before anything starts:
   ```bash
   mkdir -p ~/m16-full && cp -R lab/. ~/m16-full/ && cd ~/m16-full
   ./ci.sh
   ```
   ```
     SUCCESS: 2 rule files found
     SUCCESS: 4 rules found
     SUCCESS: 5 rules found
     SUCCESS
   Checking 'alertmanager/alertmanager.yml'  SUCCESS
   pager
   ```

3. Start the stack:
   ```bash
   docker compose up -d --build
   docker compose ps --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}'
   ```
   Twelve containers; Postgres loads 600,000 transcripts first, then the apps, then Alloy.

4. One question, all three signals, one trace ID:
   ```bash
   curl -s "localhost:8080/api/ask?q=teach+me+kubernetes"; echo
   docker compose logs --no-log-prefix api copilot | grep request | jq -c "{service, route, status, duration_ms, trace_id}"
   curl -s localhost:8080/metrics | grep "_bucket" | grep "/api/ask" | grep trace_id
   ```
   ```
   {"answer":"Try the DevOps course.","courses":["DevOps"]}
   {"service":"copilot","route":"/ask","status":200,...,"trace_id":"fdc57c..."}
   {"service":"api","route":"/api/ask","status":200,...,"trace_id":"fdc57c..."}
   http_request_duration_seconds_bucket{le="0.1",route="/api/ask"} 1.0 # {trace_id="fdc57c..."} 0.064 ...
   ```
   Save it (`TID=<that trace_id>`) and ask each store:
   ```bash
   curl -s localhost:9090/api/v1/query_exemplars --data-urlencode 'query=http_request_duration_seconds_bucket' | jq -r '.data[] | .seriesLabels.job + "  " + .exemplars[].labels.trace_id'
   curl -s -G localhost:3100/loki/api/v1/query_range --data-urlencode "query={service=~\"api|copilot\"} | trace_id=\"$TID\"" | jq -r '.data.result[].values[][1]' | cut -c1-92
   curl -s localhost:3200/api/v2/traces/$TID | jq -r '.trace.resourceSpans[] | (.resource.attributes[] | select(.key=="service.name").value.stringValue) as $s | .scopeSpans[].spans[] | "\($s)  \(.name)"'
   ```
   The exemplar for api and copilot, both log lines, and 7 spans in two services.

5. Everything wired?
   ```bash
   curl -s localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | .labels.job + "  " + .health'
   curl -s localhost:9090/api/v1/query --data-urlencode 'query=pg_up' | jq -r '.data.result[] | .metric.job + "  " + .metric.instance + "  up=" + .value[1]'
   curl -s localhost:3000/api/datasources | jq -r '.[] | .name + "  uid=" + .uid + "  " + .type'
   curl -s 'localhost:3000/api/search?query=allcsvideos' | jq -r '.[] | .uid + "  " + .title'
   ```
   Five targets `up`, `postgres  catalog-db  up=1`, three data sources, and `allcs-overview`.

6. Start the students and check the footprint:
   ```bash
   docker compose --profile load up -d load
   docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' $(docker compose ps -q)
   ```
   After ~5 minutes open http://localhost:3000 -> **allcsvideos overview**: API ~7.4 req/s, Copilot ~1.7, errors 0.00 %,
   p99 under ~10 ms, pages firing 0, the database almost idle.

7. The staged bad deploy - Copilot 1.1 adds transcript search (`ILIKE '%...%'` over 600,000 rows, no usable index):
   ```bash
   date +%T; ./deploy.sh copilot 1.1
   ```
   Within ~2 minutes the pager gets **one** notification for the whole incident:
   ```bash
   docker compose logs --no-log-prefix receiver | grep -v heartbeat
   tail -1 runs/pager.jsonl | jq -r '.status, (.groupLabels|tostring), (.alerts[] | .labels.alertname + "  " + .annotations.summary)'
   ```
   ```
   22:08:57 pager     FIRING   alerts=4 firing=4 HighErrorRate,HighLatencyP99
   firing
   {"team":"platform"}
   HighErrorRate  copilot /ask: 79.31% of requests fail
   HighErrorRate  api /api/ask: 74.23% of requests fail
   ...
   ```

8. The on-call path. **Board**: pages firing 4, the dashed deploy line where every graph bends, the database USE row
   jumping (busy time, rows read by full scans). **Exemplar** - the slowest Copilot requests of the last 3 minutes:
   ```bash
   curl -s localhost:9090/api/v1/query_exemplars --data-urlencode 'query=http_request_duration_seconds_bucket{job="copilot"}' --data-urlencode start=$(( $(date +%s) - 180 )) | jq -r '[.data[].exemplars[]] | sort_by(.value|tonumber) | reverse | .[:3][] | .labels.trace_id + "  " + .value + " s"'
   ```
   **Trace** - open the top one in Grafana (click the diamond on the latency graph, or Explore -> Tempo -> paste the
   ID): Copilot's second `SELECT`, ~1 s, in error: `canceling statement due to statement timeout`, `db.statement`
   `... WHERE transcript ILIKE ...`. **Log line** - "Logs for this trace", or:
   ```bash
   TID=<the slow trace_id>
   curl -s -G localhost:3100/loki/api/v1/query_range --data-urlencode "query={service=~\"api|copilot\"} | trace_id=\"$TID\"" | jq -r '.data.result[].values[][1]' | jq -c '{service, version, status, duration_ms, error}'
   ```
   ```
   {"service":"api","version":"1.0","status":502,"duration_ms":1429.8,"error":"copilot answered 500"}
   {"service":"copilot","version":"1.1","status":500,"duration_ms":1426.0,"error":"canceling statement due to statement timeout"}
   ```

9. Roll back, and watch the page resolve:
   ```bash
   date +%T; ./deploy.sh copilot 1.0
   sleep 200; docker compose logs --no-log-prefix receiver | grep -v heartbeat
   ```
   ```
   22:11:57 pager     FIRING   alerts=4 firing=2 HighErrorRate,HighLatencyP99
   22:12:57 pager     FIRING   alerts=3 firing=1 HighErrorRate,HighLatencyP99
   22:13:57 pager     RESOLVED alerts=2 firing=0 HighErrorRate,HighLatencyP99
   ```
   On the board, two dashed lines bracket the incident. In the video: ~4 minutes of failures (373 of 460 questions),
   the course list never failed, deploy -> page 2 m 08 s, page -> rollback 1 m 51 s. The real fix (an index that can
   serve the search, e.g. `pg_trgm`, tested on production-sized data) belongs in a pull request.

Explained but not run: kube-prometheus-stack and ServiceMonitors, Alloy as a DaemonSet, a Collector gateway with
tail sampling, HA Prometheus/Alertmanager, Thanos/Mimir, Loki/Tempo on object storage, a real paging service.

## Common mistakes
- Signals that don't share an ID: without the trace ID in exemplars and log lines, the three stores are islands.
- High-cardinality IDs in Prometheus labels or Loki stream labels: keep them in exemplars, structured metadata and spans.
- Paging on causes (like pool saturation): page on errors, latency and targets down; causes become tickets or dashboard rows.
- One page per service per alert: group pages by team so one incident is one page.
- Shipping alert or routing changes without `promtool` / `amtool` checks in CI.
- Unbounded containers: give every container a memory limit, as here.

## Clean up
```bash
cd ~/m16-full
docker compose --profile load down -v --rmi local
cd ~ && rm -rf ~/m16-full
```

## Next
[M17-L01 · SLIs, SLOs and Error Budgets](../m17-l01-slis-slos-and-error-budgets/) - turning "reliable" into a number you can manage.
