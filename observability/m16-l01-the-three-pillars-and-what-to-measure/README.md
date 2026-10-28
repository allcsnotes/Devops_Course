# M16-L01 · The Three Pillars and What to Measure
> Video: Module 16, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- Monitoring (checks for known unknowns) vs observability (asking new questions of the data you already collect).
- The three pillars - metrics, logs, traces - what each answers and what each costs (cardinality, volume, sampling); plus profiles and events.
- The four golden signals (latency, traffic, errors, saturation), RED for services and USE for resources.
- Why percentiles beat averages, and a first SLI (good requests / all requests).
- Pitfalls: vanity metrics, too many dashboards, high-cardinality labels, alerting on causes, logging everything.

## Before you start
- Docker Desktop (Compose v2), `curl`, `python3` on your laptop.
- About 1 GB free memory. The database seeds 2,000,000 rows on first start, which takes a little while.
- Linux only: the load container writes into `lab/runs/` as user 10001, so run `chmod 777 lab/runs` once.

## Files in this folder
| File | What it is |
|---|---|
| `lab/compose.yaml` | Project `m16-lab`: `db` (PostgreSQL 18.6, fake lab password), `api` (port 8080), `load` |
| `lab/api/` | The lab API (Python 3.13, pg8000 1.31.5, prometheus-client 0.26.0): JSON log line per request, `/metrics`, a pool of 4 DB connections (1 s wait, 1.5 s statement timeout); `LOG_LEVEL=debug` and `USER_LABEL=1` switch on two pitfalls |
| `lab/db/init.sql` | 24 courses and 2,000,000 course views (no index: the popular sort scans them) |
| `lab/db/migration.sql` | The staged migration: `ALTER TABLE` + `pg_sleep(30)` in one transaction |
| `lab/load/traffic.py` | Simulated users: N requests/s on a fixed schedule, 2 s timeout, 2 in 100 ask `?sort=popular`; writes `runs/<name>.csv` and `runs/<name>-pool.csv` |
| `lab/run-incident.sh` | 180 s of traffic + docker stats recorder; the migration at 75 s |
| `lab/signals.py`, `lab/sli.py` | Compute golden signals / RED / USE / mean vs percentiles, and the SLI, from a run |
| `sample-run/` | The exact run from the video (`r02`), so you can compare your numbers |

## Follow along

1. Start the lab (from this lesson's folder):
   ```bash
   cd lab
   docker compose up -d --build
   docker compose ps --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}'
   ```
   `api`, `db (healthy)` and `load` are Up.

2. The API, its log line, and its metrics:
   ```bash
   curl -s localhost:8080/api/courses | head -c 150; echo
   docker compose logs api --no-log-prefix | grep '"status": 200' | tail -1
   curl -s localhost:8080/metrics | grep -E '^(http_requests_total|db_pool_(in_use|waiting|size)) ?'
   curl -s localhost:8080/metrics | grep 'bucket{.*route="/api/courses"}'
   ```
   ```
   {"courses": [{"id": 1, "title": "DSA · part 1"}, ...
   {"ts": "...", "level": "info", "service": "api", "msg": "request", "trace_id": "e3de...", "method": "GET", "route": "/api/courses", "status": 200, "duration_ms": 3.2, "pool_wait_ms": 0.3, "db_ms": 2.8, "user": "anonymous"}
   http_requests_total{route="/api/courses",status="200"} ...
   db_pool_size 4.0
   http_request_duration_seconds_bucket{le="0.005",route="/api/courses"} ...
   ```
   Each histogram bucket includes everything below it.

3. The staged incident: 3 minutes at 20 requests/s, the migration at 75 s.
   ```bash
   ./run-incident.sh r02
   ```
   ```
   17:26:09 req=20 ok=20 err=0 p50=1ms p99=31ms pool=0/4 wait=0
   ...
   ... req=20 ok=0 err=20 ... pool=4/4 wait=20
   ...
   done: 3600 requests, 579 failed
   ```
   (Your counts will be close, not identical.) While it runs, check the containers in a second terminal - `api` stays
   Up the whole time:
   ```bash
   docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' m16-lab-api-1 m16-lab-db-1
   ```

4. Each signal, before / during / after:
   ```bash
   python3 signals.py r02 golden
   python3 signals.py r02 red
   python3 signals.py r02 use
   ```
   From the video's run:
   ```
                                before       during        after
   latency p50                    2 ms       1.00 s         2 ms
   latency p99                  374 ms       2.00 s       492 ms
   traffic (req/s)                20.0         20.0         19.7
   errors                        0.0 %       96.5 %        0.0 %
   saturation (pool)          5 % used   100 % used     6 % used
   ...
   db container (1 CPU)
     CPU utilization            17.1 %        1.6 %       21.7 %
   ```
   Errors and saturation light up; CPU does not. Waiting for a lock costs no CPU.

5. The logs say why, then one request across the pillars:
   ```bash
   docker compose logs api --no-log-prefix | grep -c '"level": "error"'
   docker compose logs api --no-log-prefix | grep -o '"error": "[^"]*"' | sort | uniq -c
   docker compose logs api --no-log-prefix | grep '"status": 500' | head -1
   ```
   ```
     76 "error": "canceling statement due to statement timeout"
    500 "error": "no free db connection"
   ```
   Copy a `trace_id` from a 500 line and grep for it - that is the jump from a spike to one request's log line:
   `docker compose logs api --no-log-prefix | grep <trace_id>`.

6. The database's view (a second staged run). Start another incident in one terminal, and about 80 s in, run these
   in the other:
   ```bash
   ./run-incident.sh r03
   ```
   ```bash
   docker compose exec db psql -U postgres -d catalog -c "SELECT pid, state, wait_event_type AS wait, left(query, 44) AS query FROM pg_stat_activity WHERE datname = 'catalog' AND pid <> pg_backend_pid()"
   docker compose exec db psql -U postgres -d catalog -c "SELECT pid, mode, granted FROM pg_locks WHERE relation = 'courses'::regclass ORDER BY granted DESC, pid"
   ```
   ```
     92 | active | Lock    | SELECT id, title FROM courses ORDER BY id      (x4)
    165 | active | Timeout | SELECT pg_sleep(30);
    165 | AccessExclusiveLock | t
     92 | AccessShareLock     | f                                             (x4)
   ```

7. Mean vs percentiles, and a first SLI (good = status 200 in under 300 ms):
   ```bash
   python3 signals.py r02 avg
   python3 sli.py r02
   ```
   ```
   mean                           9 ms       1.11 s        14 ms
   p50                            2 ms       1.00 s         2 ms
   p99                          374 ms       2.00 s       492 ms
   requests 3600   good 2955   SLI 82.08 %
   ```
   To see the video's exact numbers, copy `sample-run/*` into `runs/` and run the scripts with the video's time zone:
   `cp ../sample-run/* runs/ && TZ=Asia/Kolkata python3 signals.py r02`.

8. Pitfall: a high-cardinality label (a `user` label on a counter):
   ```bash
   USER_LABEL=1 docker compose up -d api
   docker compose exec load python traffic.py http://api:8080 30 20 c01 | tail -1
   curl -s localhost:8080/metrics | grep -c '^http_requests_total{'; curl -s localhost:8080/metrics | grep -c '^http_requests_by_user_total{'
   curl -s localhost:8080/metrics | grep '^http_requests_by_user_total{' | head -3
   curl -s localhost:8080/metrics | wc -c
   docker compose up -d api
   docker compose exec load python traffic.py http://api:8080 30 20 c02 | tail -1
   curl -s localhost:8080/metrics | grep -c '^http_requests_total{'
   curl -s localhost:8080/metrics | wc -c
   ```
   600 requests: `2` series without the label, `568` with it; `69656` bytes vs `5420`.

9. Pitfall: logging everything:
   ```bash
   docker compose exec load python traffic.py http://api:8080 30 20 c03 | tail -1
   docker compose logs api --no-log-prefix | wc -l -c
   LOG_LEVEL=debug docker compose up -d api
   docker compose exec load python traffic.py http://api:8080 30 20 c04 | tail -1
   docker compose logs api --no-log-prefix | wc -l -c
   docker compose logs api --no-log-prefix | grep '"level": "debug"' | head -2
   docker compose up -d api
   ```
   Same 600 requests: `601` lines / ~159 KB at info, `14929` lines / ~2.7 MB at debug.

## Common mistakes
- Averages: a 9 ms mean hid a 374 ms p99. Track p50, p95, p99 from histograms; never average percentiles across servers.
- Too many dashboards: start each service with one board of golden signals, and link down to USE for its resources.
- High-cardinality labels: user IDs belong in logs and traces, never in metric labels.
- Alerting on causes (CPU stayed calm while 96% failed): alert on symptoms users feel - errors and latency.
- Logging everything: one rich line per request; debug only while investigating.
- Vanity metrics and "container Up": ask of every metric "if this changes, what would we do differently?"

## Clean up
```bash
docker compose down -v --rmi local
rm -f runs/*.csv runs/*.txt runs/*.json
```

## Next
[M16-L02 · Metrics with Prometheus](../m16-l02-metrics-with-prometheus/) - exporters, scraping, labels, and PromQL from zero.
