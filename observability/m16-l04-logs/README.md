# M16-L04 · Logs
> Video: Module 16, Lesson 4. Watch it first, then follow along here.

## What you'll learn
- Structured logging: one JSON object per line, honest levels (DEBUG, INFO, WARN, ERROR), the stack trace inside the line.
- Request (correlation) IDs: created at the edge, passed in `X-Request-ID`, put on every log line, returned to the user.
- Keeping secrets and personal data out of logs with a redaction filter.
- Grafana Alloy -> Loki -> Grafana: Loki indexes labels, not text; few low-cardinality labels, then a fast scan.
- LogQL: stream selectors, line filters, `json` + label filters, and metric queries (`count_over_time`, `rate`, `unwrap`).
- ELK/OpenSearch vs Loki, retention and sampling, logs on Kubernetes, and the five pitfalls.

## Before you start
- Docker Desktop (Compose v2), `curl`, `jq`. About 2 GB free memory and 1 GB disk for the full run.
- [M16-L01](../m16-l01-the-three-pillars-and-what-to-measure/) (the three pillars) and [M16-L03](../m16-l03-dashboards-with-grafana/) (Grafana).

## Files in this folder
| File | What it is |
|---|---|
| `lab/compose.yaml` | Project `m16-logs`: `web` x2 (ports 8080-8081), `api` x2, Loki 3.7.9 (3100), Alloy v1.21.0, Grafana 13.2.4 (3000, anonymous admin - lab only), `load` (profile `load`) |
| `lab/app/logsetup.py` | JSON formatter (`exc` field for stack traces), context filter (request ID), redaction filter (`REDACT=1`) |
| `lab/app/app.py` | One image, two roles: `web` gateway (creates/propagates `X-Request-ID`) and `api` (courses, checkout, login). Staged bug: coupon `LAUNCH2026` has no expiry date. Knobs: `LOG_LEVEL`, `REDACT`, `LOG_FORMAT=text` |
| `lab/load/loadgen.py` | Students: `REQUESTS`, `WORKERS`; at request `STAGED_AT`, Lukas checks out with `LAUNCH2026` and his reference goes to `runs/staged.json` |
| `lab/alloy/config.alloy` | Docker discovery (this project only), keep `web`/`api`, labels `service`, `container`, `level` |
| `lab/loki/loki.yaml` | Single binary, filesystem chunks, TSDB index, retention 7 days via the compactor |
| `lab/grafana/provisioning/datasources/loki.yaml` | Loki data source (uid `loki`) |
| `lab/logcli.sh` | `logcli` (3.7.9, in a container on the lab network) and a `table` helper |
| `steps/config.alloy.request-id-label` | The staged mistake: `request_id` as a label |
| `steps/config.alloy.structured-metadata` | The fix: `request_id` as structured metadata |
| `steps/loki.yaml` | Adds a per-stream retention: `{level="debug"}` kept 1 day |

## Follow along

1. Start the lab:
   ```bash
   LESSON=$PWD                                   # run from this lesson's folder
   mkdir -p ~/m16-logs && cp -R lab/. ~/m16-logs/ && cd ~/m16-logs
   docker compose up -d --build
   docker compose ps --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}'
   source logcli.sh
   ```
   Seven containers: alloy, api x2, grafana, loki, web x2. (Linux only: `chmod 777 runs` so the load container can write.)

2. One request, and its two log lines from two containers:
   ```bash
   curl -si localhost:8080/api/courses/103 -H 'X-User: u4711'
   docker compose logs web --no-log-prefix | grep -v listening | jq .
   docker compose logs api --no-log-prefix | grep -v listening | jq -c .
   ```
   The response has an `X-Request-ID` header; the gateway's line and the API's line carry the same `request_id`.

3. The volume: about 15 minutes of students (~500 requests/s). Request 300,000 is Lukas, with coupon `LAUNCH2026`:
   ```bash
   docker compose run --rm -e REQUESTS=472000 -e WORKERS=24 -e STAGED_AT=300000 load
   ```
   ```
   STAGED {"at": "...", "status": 500, "x_request_id": "37722bb2...", "body": {"error": "something went wrong", "reference": "37722bb2..."}}
   ...
   done: 472,000 requests in 930 s, 5xx 59
   ```
   (Short on time? Use e.g. `REQUESTS=60000 STAGED_AT=30000`; the numbers below will be smaller.) Save Lukas's reference:
   ```bash
   REF=$(jq -r .x_request_id runs/staged.json); echo $REF
   ```

4. How many lines, and find his request:
   ```bash
   logcli instant-query -q 'sum by (service) (count_over_time({service=~"web|api"}[1h]))' | jq -r '.[] | "\(.metric.service)  \(.value[1])"'
   logcli instant-query -q 'sum(count_over_time({service=~"web|api"}[1h]))' | jq -r '.[].value[1]'
   time logcli query -q --since=1h -o raw "{service=~\"web|api\"} |= \"$REF\"" | jq -c '{service,level,msg,status}'
   ```
   ```
   1000567
   {"service":"web","level":"error","msg":"request","status":500}
   {"service":"api","level":"error","msg":"request","status":500}
   {"service":"api","level":"error","msg":"unhandled error","status":null}
   ```

5. The cause - the stack trace lives in the `exc` field:
   ```bash
   logcli query -q --since=1h -o raw "{service=\"api\"} |= \"$REF\" | json | msg=\"unhandled error\"" | jq -r .exc
   logcli query -q --since=1h -o raw "{service=\"api\"} |= \"$REF\" | json | msg=\"unhandled error\"" | jq 'del(.exc)'
   ```
   ```
     File "/app/app.py", line 35, in price_for
       if datetime.fromisoformat(c["expires"]) < datetime.now():     # TypeError when expires is None
   TypeError: fromisoformat: argument must be str
   ```

6. Full scan vs labels:
   ```bash
   logcli query -q --since=1h --stats "{service=~\"web|api\"} |= \"$REF\"" 2>&1 >/dev/null | grep -E 'Total(Lines|Bytes)P|ExecTime' | head -3
   logcli query -q --since=1h --stats "{service=\"api\", level=\"error\"} |= \"$REF\"" 2>&1 >/dev/null | grep -E 'Total(Lines|Bytes)P|ExecTime' | head -3
   ```
   Video: 1,000,567 lines / 316 MB in ~590 ms, versus 60 lines / 18 kB in ~3.6 ms.

7. The old way (Module 2): export everything to one file and grep:
   ```bash
   docker compose logs --no-log-prefix --no-color web api > all.log
   wc -l all.log; ls -lh all.log
   time grep $REF all.log | jq -c '{service,level,msg,status}'
   ```
   grep is fast (~0.2 s for 255 MB). Getting the file from every container, before it's replaced, is the hard part.

8. LogQL metric queries:
   ```bash
   logcli instant-query -q 'sum by (level) (count_over_time({service=~"web|api"}[1h]))' | table
   logcli instant-query -q 'sum by (service, status) (count_over_time({service=~"web|api"} | json | status >= 500 [1h]))' | table
   logcli instant-query -q 'topk(3, sum by (user) (count_over_time({service="web"} | json | status >= 500 [1h])))' | table
   logcli instant-query -q 'quantile_over_time(0.99, {service="web"} | json | path="/api/checkout" | unwrap duration_ms [1h]) by (service)' | table
   logcli instant-query -q 'avg_over_time({service="web"} | json | path="/api/checkout" | unwrap duration_ms [1h]) by (service)' | table
   ```
   ```
   error  119
   info  959775
   warning  40673
   api 500  1
   api 504  58
   web  28.33...        <- checkout p99 in ms
   web  5.42...         <- average
   ```
   Open http://localhost:3000 -> Explore -> Loki and run `{service=~"web|api"} |= "<your REF>"`, then
   `{service="api"} | json | status >= 500`.

9. Storage and streams:
   ```bash
   curl -s -X POST localhost:3100/flush
   docker run --rm -v m16-logs_loki-data:/loki:ro alpine:3.23.6 du -sh /loki/chunks /loki/tsdb-shipper-active /loki/wal
   ls -lh all.log | awk '{print $5, $9}'
   logcli series -q --since=1h --analyze-labels '{service=~"web|api"}'
   ```
   Video: 38 MB of chunks and a 56 KB index for 255 MB of logs; `Total Streams: 12`.

10. Pitfall: secrets in logs (`demo-password-123` is a fake value). Redaction off, then on:
    ```bash
    REDACT=0 docker compose up -d web 2>/dev/null
    curl -s localhost:8080/api/login -d '{"email": "lukas@example.com", "password": "demo-password-123"}'
    docker compose logs web --since 10s --no-log-prefix | grep login | jq -c '{msg, email, password}'
    docker compose up -d web 2>/dev/null
    curl -s localhost:8080/api/login -d '{"email": "lukas@example.com", "password": "demo-password-123"}'
    docker compose logs web --since 10s --no-log-prefix | grep login | jq -c '{msg, email, password}'
    ```
    ```
    {"msg":"login attempt","email":"lukas@example.com","password":"demo-password-123"}
    {"msg":"login attempt","email":"l***@example.com","password":"[REDACTED]"}
    ```

11. Pitfall: multi-line text logs. Switch the API to text and replay Lukas's checkout:
    ```bash
    LOG_FORMAT=text docker compose up -d api 2>/dev/null
    curl -s localhost:8080/api/checkout -H 'X-User: u4711' -d '{"course_id": 103, "coupon": "LAUNCH2026"}'
    docker compose logs api --since 20s --no-log-prefix
    logcli query -q --since=2m '{service="api"} |= "TypeError"'
    logcli query -q --since=2m -o raw '{service="api"}' | wc -l
    docker compose up -d api 2>/dev/null
    ```
    The trace becomes separate lines with no level and no request ID; the `TypeError` line alone tells you nothing.

12. Pitfall: a high-cardinality label (`request_id` as a label), staged:
    ```bash
    cp "$LESSON/steps/config.alloy.request-id-label" alloy/config.alloy
    docker compose restart alloy
    docker compose run --rm -e REQUESTS=6000 -e WORKERS=8 load | tail -n 1
    logcli series -q --since=15m --analyze-labels '{service=~"web|api"}' | head -n 7
    curl -s localhost:3100/metrics | grep -E '^loki_(ingester_memory_streams|discarded_samples_total)' | cut -d, -f3-
    ```
    ```
    Total Streams:  5012
    reason="stream_limit",... 2352
    loki_ingester_memory_streams{tenant="fake"} 5000
    ```
    Revert - and a new request still doesn't show up, because the stream limit is still full:
    ```bash
    cp "$LESSON/lab/alloy/config.alloy" alloy/config.alloy
    docker compose restart alloy 2>/dev/null
    ID=$(curl -s -o /dev/null -D - localhost:8080/api/courses | grep X-Request-ID | tr -d '\r' | cut -d' ' -f2)
    logcli query -q --since=5m -o raw "{service=\"web\"} |= \"$ID\"" | wc -l
    curl -s localhost:3100/metrics | grep -E '^loki_discarded_samples_total' | cut -d, -f3-
    curl -s -X POST localhost:3100/flush
    sleep 30; curl -s localhost:3100/metrics | grep -E '^loki_ingester_memory_streams\b'
    logcli query -q --since=15m -o raw "{service=\"web\"} |= \"$ID\"" | wc -l
    ```
    `0`, then after the flush the ingester empties, Alloy's retry goes through, and the line appears: `1`.

13. The right fix: structured metadata (attached to the line, not indexed):
    ```bash
    cp "$LESSON/steps/config.alloy.structured-metadata" alloy/config.alloy
    docker compose restart alloy 2>/dev/null
    ID=$(curl -s -o /dev/null -D - localhost:8080/api/courses/105 | grep X-Request-ID | tr -d '\r' | cut -d' ' -f2)
    sleep 5; logcli query -q --since=1m -o raw "{service=~\"web|api\"} | request_id=\"$ID\"" | jq -c '{service, msg, status}'
    logcli series -q --since=1m --analyze-labels '{service=~"web|api"}' | head -n 2
    ```
    Both lines, and `Total Streams: 3`.

14. Retention: keep debug lines only one day:
    ```bash
    diff loki/loki.yaml "$LESSON/steps/loki.yaml"
    cp "$LESSON/steps/loki.yaml" loki/loki.yaml
    docker compose restart loki 2>/dev/null
    curl -s localhost:3100/config | grep -m1 -A4 '^  retention_period:'
    ```
    ```
      retention_period: 1w
      retention_stream:
      - period: 1d
    ```

Explained but not run: Elasticsearch/Logstash/Kibana and OpenSearch, Alloy's sampling stage, logs on Kubernetes
(stdout -> `/var/log/pods` -> a DaemonSet agent).

## Common mistakes
- DEBUG in production: 25x the lines (M16-L01). Info by default; debug for one service, one investigation.
- High-cardinality labels (request IDs, user IDs): the stream limit fills and Loki discards even normal lines. Use structured metadata or keep the value in the line.
- Multi-line text stack traces: one event becomes many unrelated entries. Log JSON with the trace inside, or join lines with Alloy's multiline stage.
- Secrets and personal data: redact in the app, scan for leaks; better never pass them to the logger.
- No retention: Loki's default keeps logs forever. Set `retention_period` (and the compactor) on day one.
- Promtail in new setups: it reached end of life on March 2, 2026 - use Alloy.

## Clean up
```bash
cd ~/m16-logs
docker compose --profile load down -v --rmi local
cd ~ && rm -rf ~/m16-logs
```

## Next
[M16-L05 · Distributed Tracing](../m16-l05-distributed-tracing/) - OpenTelemetry, Tempo and Jaeger, following a request across services.
