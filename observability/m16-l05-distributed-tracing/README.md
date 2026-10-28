# M16-L05 · Distributed Tracing
> Video: Module 16, Lesson 5. Watch it first, then follow along here.

## What you'll learn
- Traces and spans: trace ID, span ID, parent, kind, attributes, events, status - the tree behind one request.
- W3C Trace Context: the `traceparent` header (version, trace ID, parent ID, flags), injected and extracted on every hop.
- OpenTelemetry: API, SDK, auto-instrumentation (`opentelemetry-instrument`), the Collector, and OTLP (4317 gRPC / 4318 HTTP).
- Reading a waterfall to find an N+1 query on an unindexed table, and fixing it (index + batching).
- Linking the pillars: logs -> trace, trace -> logs, metrics -> trace (exemplars).
- Head vs tail sampling, Jaeger vs Tempo, and the five pitfalls.

## Before you start
- Docker Desktop (Compose v2), `curl`, `jq`, a browser. About 3 GB free memory (ten containers).
- [M16-L04](../m16-l04-logs/) (Loki, request IDs) and [M16-L02](../m16-l02-metrics-with-prometheus/) (histograms).

## Files in this folder
| File | What it is |
|---|---|
| `lab/compose.yaml` | Project `m16-tracing`: `bff` (storefront-bff, port 8080), `api`, `catalog` (catalog-service), `db` (PostgreSQL 18.6), Collector contrib 0.163.1 (its metrics on 8888), Jaeger 2.22.0 (UI 16686), Tempo 3.1.0 (3200), Loki 3.7.9 (3100), Prometheus v3.15.0 with exemplar storage (9090), Grafana 13.2.4 (3000, anonymous admin - lab only), `load` (profile `load`) |
| `lab/app/` | One Python image for the three services: Flask + requests + psycopg, OpenTelemetry 1.45.1 / 0.66b1, started with `opentelemetry-instrument`. One manual span (`check enrollments`); JSON logs with `trace_id`, `span_id`, `traceparent_in`. Knobs: `QUERY_MODE`, `FAULT_RATE`, `LEGACY_CLIENT`, `SPAN_PER_ID` |
| `lab/db/init.sql` | Courses and 2,000,000 enrollments - no index on `student_id` (staged) |
| `lab/otelcol/config.yaml` | OTLP in; memory_limiter + batch; traces to Jaeger **and** Tempo, logs to Loki |
| `lab/otelcol/config-tail.yaml` | Same plus tail sampling: keep errors, anything > 500 ms, 10% of the rest |
| `lab/otelcol/config-v1.yaml` | First draft with the old `otlp`/`otlphttp` exporter names (shows the deprecation warning) |
| `lab/tempo/`, `lab/loki/`, `lab/prometheus/` | Backend configs |
| `lab/grafana/provisioning/datasources/datasources.yaml` | Tempo, Loki, Prometheus with trace-to-logs, logs-to-trace and exemplar links |
| `lab/load/traffic.py`, `lab/load.sh`, `lab/count-errors.sh` | Page loads at a fixed rate; error traces stored in Tempo since the last load |

## Follow along

1. Start the lab and check the instrumentation packages:
   ```bash
   LESSON=$PWD                                   # run from this lesson's folder
   mkdir -p ~/m16-tracing && cp -R lab/. ~/m16-tracing/ && cd ~/m16-tracing
   docker compose up -d --build
   docker compose ps --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}'
   docker compose exec catalog pip list 2>/dev/null | grep -i opentelemetry
   ```
   Wait until `db` is healthy (it seeds 2 million rows).

2. Lukas's problem, restaged: one page load a second for a minute.
   ```bash
   N=60 RATE=1 docker compose run --rm load
   ```
   ```
   sent=60 ok=45 failed=15 p50=2883ms p95=5038ms
   ```

3. One page load, and three log lines that each say "I was slow":
   ```bash
   curl -s 'localhost:8080/catalog?user=u3181' | jq -c .
   curl -s -o /dev/null -w '%{http_code} in %{time_total} s\n' 'localhost:8080/catalog?user=u3181'
   docker compose logs --no-log-prefix --since 5s bff api catalog | grep '"request"' | jq -c '{service, status, duration_ms}'
   docker compose logs --no-log-prefix --since 5s bff api catalog | grep '"request"' | jq -c '{service, trace_id, span_id}'
   ```
   Same `trace_id` in all three services, a different `span_id` each. Keep it: `TID=<that trace_id>`.

4. The header on the wire, and who the parents are:
   ```bash
   docker compose logs --no-log-prefix api catalog | grep $TID | grep '"request"' | jq -r '"\(.service): traceparent: \(.traceparent_in)"'
   curl -s localhost:16686/api/v3/traces/$TID | jq -r '.result.resourceSpans[] | (.resource.attributes[] | select(.key=="service.name").value.stringValue) as $s | .scopeSpans[].spans[] | select(.name != "SELECT") | "\(.spanId)  parent \(.parentSpanId // "none")  \($s)  \(.name)"'
   ```
   ```
   api: traceparent: 00-941cb7547f0b480d426721ee21c07b50-d46d30a9ba1ba93a-03
   catalog: traceparent: 00-941cb7547f0b480d426721ee21c07b50-19fd9c2515811296-03
   d46d30a9ba1ba93a  parent b8aec1ec3fa7fd18  storefront-bff  GET
   19fd9c2515811296  parent ba78f5ac58e67035  api  GET
   ```
   Same trace ID on every hop; the parent ID is the caller's client span.

5. Start a trace yourself with the W3C spec's example header:
   ```bash
   curl -sv -o /dev/null -H 'traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01' 'localhost:8080/catalog?user=u3181' 2>&1 | grep '^[<>] [A-Za-z]'
   docker compose logs --no-log-prefix --since 5s bff api catalog | grep '"request"' | jq -r '"\(.service): \(.traceparent_in)"'
   ```
   All three continue trace `4bf92f35...`, and the flags stay `01`.

6. Read the waterfall. Open Jaeger at http://localhost:16686 -> service `storefront-bff` -> Find Traces, and open your
   ~1.2 s trace: 3 services, 19 spans. Inside catalog-service, `check enrollments` takes ~1.1 s with **12 `SELECT`
   children one after another** - the N+1 staircase. In the terminal:
   ```bash
   curl -s localhost:16686/api/v3/traces/$TID | jq '[.result.resourceSpans[].scopeSpans[].spans[] | select(.name=="SELECT")][1] | {name, kind, startTimeUnixNano, endTimeUnixNano, attributes: [.attributes[] | {(.key): (.value | to_entries[0].value)}] | add, status}'
   curl -s localhost:16686/api/v3/traces/$TID | jq -c '.result.resourceSpans[].scopeSpans[].spans[] | select(.name=="check enrollments") | .events[] | {name, attributes}'
   ```
   `db.statement` shows placeholders (`%s`), not values. The same trace is in Grafana (http://localhost:3000 -> Explore -> Tempo).

7. Is it only this request? TraceQL in Tempo:
   ```bash
   curl -s -G localhost:3200/api/search --data-urlencode 'q={ span.db.system = "postgresql" } | count() > 10' --data-urlencode 'limit=4' | jq -r '.traces[] | "\(.traceID)  \(.rootServiceName)  \(.rootTraceName)  \(.durationMs) ms"'
   ```
   The `4bf92f35...` row says `<root span not yet received>`: your curl started that trace but sent no span.

8. Why each query is slow, and fix one - an index:
   ```bash
   docker compose exec db psql -U postgres -d catalog -c 'EXPLAIN ANALYZE SELECT 1 FROM enrollments WHERE student_id = 3181 AND course_id = 103 LIMIT 1'
   docker compose exec db psql -U postgres -d catalog -c 'CREATE INDEX enrollments_student_course ON enrollments (student_id, course_id)'
   docker compose exec db psql -U postgres -d catalog -c 'EXPLAIN ANALYZE SELECT 1 FROM enrollments WHERE student_id = 3181 AND course_id = 103 LIMIT 1'
   curl -s -o /dev/null -w '%{http_code} in %{time_total} s\n' 'localhost:8080/catalog?user=u3181'
   curl -s -o /dev/null -w '%{http_code} in %{time_total} s\n' 'localhost:8080/catalog?user=u3181'
   ```
   `Parallel Seq Scan ... Rows Removed by Filter: 666405` becomes `Index Only Scan`; the page drops to ~11 ms.

9. Fix two - batch the 12 queries into one:
   ```bash
   QUERY_MODE=batched docker compose up -d catalog 2>&1 | tail -1
   curl -s -o /dev/null -w '%{http_code} in %{time_total} s\n' 'localhost:8080/catalog?user=u3181'
   N=60 RATE=1 docker compose run --rm load
   ```
   The trace now has 8 spans and one `SELECT`. Load: `sent=60 ok=60 failed=0 p50=15ms p95=132ms`.

10. Link the pillars. In Grafana Explore -> Loki, query `{service_name=~"storefront-bff|api|catalog-service"} | trace_id="<TID>"` (or filter by
    the trace ID text) - in the video, 4 lines from 3 services for one page load. The `trace_id` field links to Tempo. In the Tempo view, **Logs for this trace** goes back to
    Loki. And the bff's histogram carries exemplars:
    ```bash
    curl -s localhost:8080/metrics | grep -E '^http_request_duration_seconds_bucket.*#' | head -3
    ```
    ```
    http_request_duration_seconds_bucket{le="0.05",route="/catalog"} 197.0 # {trace_id="85d7..."} 0.0115 1792589496.19
    ```
    In Grafana, a Prometheus panel on this histogram shows them as diamonds that open the trace.

11. Sampling, measured. Stage a 3% fault rate, then compare no sampling, tail sampling and head sampling:
    ```bash
    QUERY_MODE=batched FAULT_RATE=0.03 docker compose up -d catalog 2>&1 | tail -1
    docker compose restart otelcol 2>&1 | tail -1
    ./load.sh 300 10
    sleep 30; curl -s localhost:8888/metrics | grep -E '^otelcol_(receiver_accepted|exporter_sent)_spans'
    ./count-errors.sh
    ```
    ```bash
    OTELCOL_CONFIG=config-tail.yaml docker compose up -d otelcol 2>&1 | tail -1
    ./load.sh 300 10
    sleep 30; curl -s localhost:8888/metrics | grep -E '^otelcol_(receiver_accepted|exporter_sent)_spans|global_count_traces_sampled'
    ./count-errors.sh
    ```
    ```bash
    docker compose up -d otelcol 2>&1 | tail -1
    BFF_SAMPLER=parentbased_traceidratio BFF_SAMPLER_ARG=0.1 docker compose up -d bff 2>&1 | tail -1
    ./load.sh 300 10
    sleep 30; curl -s localhost:8888/metrics | grep -E '^otelcol_(receiver_accepted|exporter_sent)_spans'
    ./count-errors.sh
    ```
    | | spans in | spans out | error traces stored |
    |---|---|---|---|
    | No sampling | 2,397 | 2,397 | 3 of 3 |
    | Tail sampling | 2,396 | 228 | 4 of 4 |
    | Head sampling 10% | 312 | 312 | 0 of 14 |

    (The video's numbers; the Collector's counters are cumulative since its last restart.) Reset:
    ```bash
    QUERY_MODE=batched docker compose up -d bff catalog 2>&1 | tail -1
    ```

12. The deprecation warning from the first Collector draft:
    ```bash
    OTELCOL_CONFIG=config-v1.yaml docker compose up -d otelcol 2>&1 | tail -1
    sleep 5; docker compose logs --no-log-prefix otelcol | grep -o '"otlp[a-z]*" alias is deprecated; use "[a-z_]*" instead' | sort -u
    docker compose up -d otelcol 2>&1 | tail -1
    ```

13. Pitfall: broken propagation (an un-instrumented client between api and catalog):
    ```bash
    QUERY_MODE=batched LEGACY_CLIENT=1 docker compose up -d api 2>&1 | tail -1
    curl -s -o /dev/null -w '%{http_code} in %{time_total} s\n' 'localhost:8080/catalog?user=u3181'
    docker compose logs --no-log-prefix --since 5s bff api catalog | grep '"request"' | jq -c '{service, trace_id, traceparent_in}'
    ```
    catalog gets `"traceparent_in":null` and a new trace ID: Jaeger shows two traces for one request.

14. Pitfall: high-cardinality span names:
    ```bash
    QUERY_MODE=batched docker compose up -d api 2>&1 | tail -1
    curl -s 'localhost:16686/api/v3/operations?service=catalog-service' | jq -r '.operations[].name'
    SPAN_PER_ID=1 docker compose up -d catalog 2>&1 | tail -1
    sleep 5; ./load.sh 100 10
    sleep 10; curl -s 'localhost:16686/api/v3/operations?service=catalog-service' | jq '.operations | length'
    curl -s 'localhost:16686/api/v3/operations?service=catalog-service' | jq -r '.operations[].name' | head -4
    ```
    3 span names before; ~1,200 after (`check course 107 for u10801`, ...).

## Common mistakes
- Broken propagation: one un-instrumented hop splits the trace. Use instrumented clients or inject the context by hand; check proxies, queues and background jobs.
- Sampling away the errors: head sampling at 10% kept 0 of 14 failures. Keep errors and slow traces with tail policies.
- High-cardinality span names: name spans by the kind of work; put IDs in attributes.
- Traces as an island: put the trace ID in every log line and add exemplars to histograms.
- Instrumenting everything by hand: 18 of 19 spans here came from auto-instrumentation; add manual spans only for business steps.
- Old Collector exporter names (`otlp`, `otlphttp`) are deprecated in 0.163: use `otlp_grpc` / `otlp_http`.

## Clean up
```bash
cd ~/m16-tracing
docker compose --profile load down -v --rmi local
cd ~ && rm -rf ~/m16-tracing /tmp/load-start
```

## Next
[M16-L06 · Alerting](../m16-l06-alerting/) - Alertmanager, alerting on symptoms not causes, routing, and avoiding alert fatigue.
