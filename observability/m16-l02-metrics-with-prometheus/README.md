# M16-L02 · Metrics with Prometheus
> Video: Module 16, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- The pull model: apps and exporters show a `/metrics` page, Prometheus scrapes it on a schedule; push only for short batch jobs (Pushgateway).
- The data model (metric name + labels = one series) and the four metric types: counter, gauge, histogram, summary.
- Instrumenting Course Copilot with the official Python client: a counter, a gauge and a histogram.
- PromQL from zero: selectors, range vectors, `rate`, `sum by`, error ratios, `histogram_quantile`, `increase`, `offset`.
- Recording rules checked with `promtool`, hot reload, retention in the config file.
- Pitfalls: too-short rate windows, counter resets, high cardinality, averaging percentiles, scraping too often.

## Before you start
- Docker Desktop (Compose v2; the video used v5.1.4), `curl`, `jq`.
- The course app copy at the repo root: [`allcsvideos/`](../../allcsvideos/) (this lesson adds metrics to its `copilot` service).
- [M16-L01](../m16-l01-the-three-pillars-and-what-to-measure/) for golden signals and percentiles.

## Files in this folder
| File | What it is |
|---|---|
| `changes/copilot/app/main.py` | Copilot with metrics: `copilot_requests_total{route,code}`, `copilot_requests_in_flight`, `copilot_courses_indexed`, `copilot_request_duration_seconds` (buckets 25 ms - 2.5 s), a `/metrics` route, and lab knobs `MODEL_DELAY_MS`, `FAULT_RATE`, `TRACK_USERS` |
| `changes/copilot/requirements.txt` | Adds `prometheus-client==0.26.0` |
| `changes/copilot/tests/test_health.py` | Adds a test that `/metrics` counts requests |
| `lab/compose.yaml` | Project `m16-metrics`: copilot-1 (port 8000) and copilot-2, node exporter v1.12.1 (9100), Prometheus v3.15.0 (9090), and a `loadgen` (profile `load`) |
| `lab/prometheus/prometheus.yml` | Scrape every 15 s: jobs `prometheus`, `node`, `copilot` (two targets, label `env: lab`) |
| `lab/loadgen/loadgen.py` | Students asking questions: `RATE` per second (10), `USERS` different students (50) |
| `lab/pq.sh` | `pq 'PromQL'`: query the HTTP API and print one line per series |
| `steps/rules-broken.yml`, `steps/rules.yml` | The recording rules: first with the staged syntax error, then fixed |
| `steps/prometheus.yml` | Config v2: adds `rule_files` and retention 7d / 1GB |

## Follow along

1. Build the lab folder: the platform's copilot plus this lesson's changes.
   ```bash
   LESSON=$PWD                                   # run from this lesson's folder
   mkdir -p ~/m16-metrics && cp -R lab/. ~/m16-metrics/
   cp -R ../../allcsvideos/copilot ~/m16-metrics/copilot
   cp -R changes/copilot/. ~/m16-metrics/copilot/
   cd ~/m16-metrics
   docker compose up -d --build
   ```

2. Lukas's problem, checked by hand:
   ```bash
   docker compose ps --format "table {{.Service}}\t{{.Status}}"
   curl -s localhost:8000/health; echo
   for i in $(seq 20); do curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" "localhost:8000/ask?q=docker"; done
   ```
   20 times `200`, between a few and ~480 ms. Twenty requests can't tell you much.

3. Read the page Prometheus will read:
   ```bash
   curl -s localhost:8000/metrics | wc -l
   curl -s localhost:8000/metrics | grep "^# TYPE"
   curl -s localhost:8000/metrics | grep copilot_
   ```
   ```
   copilot_requests_total{code="200",route="/health"} 6.0
   copilot_requests_total{code="200",route="/ask"} 20.0
   copilot_requests_in_flight 0.0
   copilot_courses_indexed 5.0
   copilot_request_duration_seconds_bucket{le="0.025",route="/ask"} 2.0
   ...
   copilot_request_duration_seconds_bucket{le="+Inf",route="/ask"} 20.0
   copilot_request_duration_seconds_count{route="/ask"} 20.0
   ```
   Buckets are cumulative; the client adds `_total` to counters.

4. An exporter speaks the same format:
   ```bash
   curl -s localhost:9100/metrics | wc -l
   curl -s localhost:9100/metrics | grep -E "^node_(load1|memory_MemAvailable_bytes|cpu_seconds_total\{cpu=\"0\")"
   curl -s localhost:9100/metrics | grep -E "^node_filesystem_avail_bytes" | head -3
   ```

5. Targets. Open http://localhost:9090 -> Status -> Target health, or use the API:
   ```bash
   curl -s localhost:9090/api/v1/targets | jq -r ".data.activeTargets[] | [.labels.job, .labels.instance, .health] | @tsv"
   ```
   Four targets, all `up`. Now break one on purpose:
   ```bash
   docker compose stop copilot-2
   sleep 20
   curl -s localhost:9090/api/v1/targets | jq -r ".data.activeTargets[] | select(.health==\"down\") | .labels.instance, .lastError"
   curl -s localhost:9090/api/v1/query --data-urlencode "query=up" | jq -r ".data.result[] | [.metric.instance, .value[1]] | @tsv"
   ```
   ```
   copilot-2:8000
   Get "http://copilot-2:8000/metrics": dial tcp: lookup copilot-2 on 127.0.0.11:53: no such host
   copilot-2:8000	0
   ```

6. Bring it back and start the load (10 questions a second from 50 students):
   ```bash
   docker compose start copilot-2
   docker compose --profile load up -d loadgen
   sleep 30; docker compose logs loadgen
   ```
   ```
   loadgen-1  | 11:54:18 sent 302  ok 293  failed 7
   ```
   Wait a few minutes before the next steps so the 5-minute windows fill up.

7. PromQL from zero - the raw API answer, then the `pq` helper:
   ```bash
   curl -s localhost:9090/api/v1/query --data-urlencode 'query=copilot_requests_total{instance="copilot-1:8000", route="/ask"}' | jq .
   source pq.sh
   pq 'copilot_requests_total'
   pq 'copilot_requests_total{route="/ask", code=~"5.."}'
   pq 'copilot_requests_total{instance="copilot-1:8000", route="/ask", code="200"}[1m]'
   pq 'rate(copilot_requests_total{instance="copilot-1:8000", route="/ask", code="200"}[1m])'
   ```
   ```
   ... route=/ask   340 413 487 558          <- a range vector: four samples, 15 s apart
   ... route=/ask   4.844444444444444        <- rate: (558 - 340) / 45 s
   ```

8. Totals, the error ratio, and latency:
   ```bash
   pq 'sum by (code) (rate(copilot_requests_total{route="/ask"}[5m]))'
   pq 'sum(rate(copilot_requests_total{route="/ask", code=~"5.."}[5m])) / sum(rate(copilot_requests_total{route="/ask"}[5m]))'
   pq 'histogram_quantile(0.95, sum by (le) (rate(copilot_request_duration_seconds_bucket{route="/ask"}[5m])))'
   pq 'histogram_quantile(0.5, sum by (le) (rate(copilot_request_duration_seconds_bucket{route="/ask"}[5m])))'
   pq 'sum(rate(copilot_request_duration_seconds_sum{route="/ask"}[5m])) / sum(rate(copilot_request_duration_seconds_count{route="/ask"}[5m]))'
   ```
   ```
   code=200   9.71...
   code=500   0.29...
      0.0291...       <- 2.9 % fail: Prometheus found the staged 3 %
      0.409...        <- p95
      0.087...        <- median
      0.121...        <- the mean hides the tail
   ```
   Try the same queries in the UI's Graph tab over 15 minutes.

9. `increase`, `offset`, and node exporter queries:
   ```bash
   pq 'increase(copilot_requests_total{route="/ask", code="500"}[5m])'
   pq 'rate(copilot_requests_total{route="/ask", code="500"}[5m]) * 300'
   pq 'sum(rate(copilot_requests_total{route="/ask"}[1m]))'
   pq 'sum(rate(copilot_requests_total{route="/ask"}[1m] offset 5m))'
   pq 'sum(rate(copilot_requests_total{route="/ask"}[1m] offset 10m))'
   pq 'copilot_requests_in_flight'
   pq 'count(node_cpu_seconds_total{mode="idle"})'
   pq '100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[1m])))'
   pq 'node_memory_MemAvailable_bytes / 1024^3'
   ```
   `increase` is not a whole number - it extrapolates to the window edges. The `offset 10m` query is empty if the
   copilots weren't running yet.

10. Recording rules. Load the broken version first and let `promtool` catch it:
    ```bash
    cp "$LESSON/steps/rules-broken.yml" prometheus/rules.yml
    docker compose exec prometheus promtool check rules /etc/prometheus/rules.yml
    ```
    ```
      FAILED:
    ... could not parse expression: 1:20: parse error: unexpected identifier "rate" in aggregation
    ```
    `sum by (...)` needs its argument in brackets. Fix it, add `rule_files` and retention to the config, check, reload:
    ```bash
    cp "$LESSON/steps/rules.yml" prometheus/rules.yml
    cp "$LESSON/steps/prometheus.yml" prometheus/prometheus.yml
    docker compose exec prometheus promtool check rules /etc/prometheus/rules.yml
    docker compose exec prometheus promtool check config /etc/prometheus/prometheus.yml
    curl -s -X POST localhost:9090/-/reload && echo reloaded
    curl -s localhost:9090/api/v1/status/runtimeinfo | jq -r .data.storageRetention
    ```
    `SUCCESS: 3 rules found`, `reloaded`, `1w or 1GiB`. (Reload works because compose starts Prometheus with
    `--web.enable-lifecycle`.) After a minute:
    ```bash
    pq 'job_code:copilot_requests:rate5m'
    pq 'job:copilot_errors:ratio_rate5m'
    pq 'job:copilot_latency_seconds:p95_5m'
    ```

11. Pitfall 1 - a rate window that is too short:
    ```bash
    pq 'rate(copilot_requests_total{route="/ask", code="200"}[15s])' | wc -l
    pq 'rate(copilot_requests_total{route="/ask", code="200"}[1m])'
    ```
    `0` lines over 15 s (one sample only); both series over 1 minute. Use at least four scrape intervals.

12. Pitfall 2 - counter resets:
    ```bash
    pq 'copilot_requests_total{instance="copilot-1:8000", route="/ask", code="200"}'
    docker compose restart copilot-1
    sleep 30
    pq 'copilot_requests_total{instance="copilot-1:8000", route="/ask", code="200"}'
    pq 'resets(copilot_requests_total{instance="copilot-1:8000", route="/ask", code="200"}[10m])'
    pq 'rate(copilot_requests_total{instance="copilot-1:8000", route="/ask", code="200"}[5m])'
    ```
    The raw counter drops (2307 -> 133 in the video); `resets` says `1`; `rate` keeps going (~4.8/s).

13. Pitfall 3 - high cardinality (a `user_id` label on the histogram), staged:
    ```bash
    pq 'prometheus_tsdb_head_series'
    pq 'count by (job) ({__name__=~".+"})'
    pq 'process_resident_memory_bytes{job="prometheus"} / 1024^2'
    TRACK_USERS=1 USERS=3000 docker compose --profile load up -d
    sleep 240
    pq 'prometheus_tsdb_head_series'
    pq 'count by (job) ({__name__=~".+"})'
    pq 'count(count by (user_id) (copilot_request_duration_seconds_count))'
    pq 'process_resident_memory_bytes{job="prometheus"} / 1024^2'
    pq 'scrape_samples_scraped{job="copilot"}'
    ```
    In the video: copilot series 96 -> 18,336, total 2,773 -> 20,563, Prometheus memory ~116 -> ~160 MB, for 1,539
    students. Revert, and queries drop back - but the head keeps the old series until its next two-hour block:
    ```bash
    docker compose --profile load up -d
    pq 'count by (job) ({__name__=~".+"})'
    pq 'prometheus_tsdb_head_series'
    ```

14. Pitfall 4 - never average percentiles:
    ```bash
    pq 'histogram_quantile(0.95, sum by (le, route) (rate(copilot_request_duration_seconds_bucket[5m])))'
    pq 'avg(histogram_quantile(0.95, sum by (le, route) (rate(copilot_request_duration_seconds_bucket[5m]))))'
    pq 'histogram_quantile(0.95, sum by (le) (rate(copilot_request_duration_seconds_bucket[5m])))'
    ```
    `/health` 0.024 and `/ask` 0.409 average to 0.216; the real p95 of all requests is 0.404. Sum the buckets first.

## Common mistakes
- A `rate()` window shorter than ~4 scrape intervals: empty or noisy results.
- Graphing raw counters: they grow forever and drop on restart. Always `rate()` them.
- Unbounded label values (user IDs, emails, URLs with IDs): every value is a new series in memory. Keep labels to small sets like route, code, instance.
- Averaging or summing percentiles: sum histogram buckets by `le`, then `histogram_quantile`. Prefer histograms over summaries.
- Scraping every second: 15x the samples and the load. 15-60 s suits almost everything.
- Loading rules without `promtool check rules` first.
- Prometheus 3.15 moved retention into the config file (`storage.tsdb.retention`); the old command-line flags are deprecated.

## Clean up
```bash
cd ~/m16-metrics
docker compose --profile load down -v --rmi local
cd ~ && rm -rf ~/m16-metrics
```

## Next
[M16-L03 · Dashboards with Grafana](../m16-l03-dashboards-with-grafana/) - building dashboards people actually read.
