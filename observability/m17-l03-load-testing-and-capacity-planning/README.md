# M17-L03 · Load Testing and Capacity Planning
> Video: Module 17, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- The six common test shapes: smoke, average-load, stress, spike, soak and breakpoint.
- Writing k6 tests in JavaScript: VUs, iterations, scenarios and executors, checks and thresholds (your SLOs).
- Closed vs open model, and how a closed test hides a stall (coordinated omission).
- Finding the breaking point with a ramping-arrival-rate test streamed to Prometheus, and reading the "knee".
- Little's law, utilisation, and a capacity plan: capacity per instance, peak estimate, headroom, N+1.
- Using a short load test as a CI gate (k6 exits 99 when a threshold fails).

## Before you start
- Docker Desktop (Compose v2) and `curl`.
- The SLOs from [M17-L01](../m17-l01-slis-slos-and-error-budgets/) and Prometheus/Grafana from Module 16.
- Free ports 8080 (API), 9090 (Prometheus), 3000 (Grafana).
- Images used (pinned): `grafana/k6:2.3.0`, `postgres:18.6-alpine3.24`, `prom/prometheus:v3.15.0`, `grafana/grafana:13.2.4`;
  the API is built from `lab/api/Dockerfile`.
- k6 runs in a container through the `./k6` wrapper, so you don't have to install it. If you installed k6 v2.3.0 on your
  laptop, you can use `k6` instead of `./k6` (the tests then default to `http://localhost:8080`).

## Files in this folder
| File | What it is |
|---|---|
| `lab/compose.yaml` | The API (exactly 1 CPU), its catalog database, Prometheus with the remote-write receiver on, Grafana, and a `k6` tool service |
| `lab/api/` | The API: `GET /api/courses?user=U` ranks the list for one student (about 18 ms of real CPU), one worker at a time, 503 "busy" after 1.5 s in the queue |
| `lab/k6` | Wrapper: `./k6 run tests/smoke.js` runs k6 2.3.0 inside the lab network |
| `lab/tests/slo.js` | The SLOs as thresholds (`http_req_failed rate<0.001`, `p(99)<500`), the base URL, random students, one URL tag |
| `lab/tests/smoke.js` | 2 VUs for 20 s, with checks and 1 s think time |
| `lab/tests/load.js` | Average load, open model: `constant-arrival-rate`, `RATE` (default 20/s) for `DURATION` (default 40 s) |
| `lab/tests/closed.js`, `lab/tests/open.js` | The same ~20 requests/s, closed model vs open model |
| `lab/tests/breakpoint.js` | `ramping-arrival-rate` from 10 to 150/s, stops itself when more than 5 % fail |
| `lab/tests/spike.js` | The launch: 5/s jumping to 150/s in 10 s |
| `lab/tests/cache.js` | Pitfall: the same student every time, so the cache answers |
| `lab/ci/load-gate.sh` | CI step after a staging deploy: 35 requests/s for 30 s with the SLO thresholds |
| `lab/grafana/` | Data source + dashboard **allcsvideos · load test (k6 + API)** |

## Follow along
1. Start the lab and check k6.
   ```bash
   cd lab
   docker compose up -d --build
   docker compose ps --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}'
   ./k6 version
   ```
   ```
   k6 v2.3.0 (commit/e088784614, go1.27.1, linux/arm64)
   ```

2. The launch evening (the video's hook): a spike from 5 to 150 requests a second, streamed to Prometheus.
   ```bash
   ./k6 run -o experimental-prometheus-rw --tag testid=launch tests/spike.js; echo "exit code: $?"
   ```
   ```
       ✗ 'p(99)<500' p(99)=6.14s
       ✗ 'rate<0.001' rate=51.93%
       http_reqs......................: 4396   87.87315/s
   exit code: 99
   ```
   The API answers about 55 a second and no more; the rest wait, then get 503.

3. Smoke test first: prove the script and the system work.
   ```bash
   ./k6 run tests/smoke.js
   ```
   ```
       ✓ 'p(99)<500' p(99)=45.26ms
       ✓ 'rate<0.001' rate=0.00%
       ✓ status is 200
       ✓ has 5 courses
       http_reqs......................: 40     1.937599/s
   ```

4. Average load in the open model: 20 new iterations every second for 40 seconds.
   ```bash
   ./k6 run -o experimental-prometheus-rw --tag testid=average tests/load.js; echo "exit code: $?"
   ```
   ```
       http_req_duration..............: avg=20.25ms min=17.02ms med=19.47ms max=78.85ms p(90)=21.5ms  p(95)=23.41ms
       http_reqs......................: 800    19.998555/s
   exit code: 0
   ```

5. Coordinated omission, for real. You need two terminals, both in `lab/`. In terminal 1 start the closed test; in
   terminal 2, right after, freeze the API for 5 seconds, 15 seconds in.
   ```bash
   # terminal 1
   ./k6 run -o experimental-prometheus-rw --tag testid=closed tests/closed.js
   ```
   ```bash
   # terminal 2
   sleep 15; docker compose pause api; sleep 5; docker compose unpause api
   ```
   Then repeat both with `tests/open.js` and `--tag testid=open`. In the video:
   ```
   closed: http_reqs 677 ... p(95)=158.23ms   http_req_failed 0.00%
   open:   http_reqs 800 ... p(95)=3.89s      http_req_failed 3.75%  30 out of 800   vus max=97
   ```
   Same server, same stall. The closed model simply stopped sending while it waited.

6. Find the limit with the breakpoint test. It stops itself when more than 5 % fail.
   ```bash
   ./k6 run -o experimental-prometheus-rw --tag testid=breakpoint tests/breakpoint.js; echo "exit code: $?"
   ```
   ```
       ✗ 'rate<0.05' rate=6.63%
   breakpoint ✗ [==============>-----------------------] 061/100 VUs  0m58.0s/2m20s  067.99 iters/s
   ERRO[0058] thresholds on metrics 'http_req_failed' were crossed; at least one has abortOnFail enabled, stopping test prematurely
   exit code: 99
   ```

7. Open Grafana at http://localhost:3000 (user `admin`, password `fake-admin-pass-123`, fake lab password), dashboard
   **allcsvideos · load test (k6 + API)**. Requests per second climb with the ramp until about 50/s, then stop
   climbing while 503s appear; p99 latency "knees" past the 500 ms line; in-flight requests jump to nearly 100.

8. Check the capacity plan's numbers: 35/s per instance (about 65 % busy) and 50/s (about 93 % busy).
   ```bash
   ./k6 run -o experimental-prometheus-rw --tag testid=rate-35 -e RATE=35 -e DURATION=60s tests/load.js; echo "exit code: $?"
   ./k6 run -o experimental-prometheus-rw --tag testid=rate-50 -e RATE=50 -e DURATION=60s tests/load.js; echo "exit code: $?"
   ```
   In the video: p99 35.94 ms at 35/s, p99 271.48 ms at 50/s (still passing, but close to the knee).

9. The capacity plan from the lesson, on paper:

   | Step | Number |
   |---|---|
   | One instance saturates at | about 54 requests/s (1 / 0.0185 s) |
   | Planned load per instance | 35/s, about 65 % busy |
   | Launch peak | 60,000 emails x 30 % open in 1 h x 10 calls = 180,000 calls/h = 50/s, x 4 for the burst = 200/s |
   | Instances | 200 / 35 = 5.7, round up to 6, plus 1 (N+1) = **7** |
   | Check | 7 up: about 29/s each; 1 down: 6 carry 33/s each, still under 35 |

10. The load test as a CI gate. Staged: version 1.1 does twice the work per request.
    ```bash
    API_VERSION=1.1 API_WORK=200000 docker compose up -d api
    sleep 5; curl -s localhost:8080/healthz
    sh ci/load-gate.sh; echo "exit code: $?"
    ```
    ```
    alive 1.1
        ✗ 'p(99)<500' p(99)=3.55s
        ✗ 'rate<0.001' rate=32.80%
    exit code: 99
    ```
    Roll back to 1.0 and run the same gate:
    ```bash
    docker compose up -d api
    sleep 5; curl -s localhost:8080/healthz
    sh ci/load-gate.sh; echo "exit code: $?"
    ```
    ```
    alive 1.0
        ✓ 'p(99)<500' p(99)=162.15ms
        ✓ 'rate<0.001' rate=0.00%
    exit code: 0
    ```

11. Pitfall: the cache-warm test. The same student every time, at 150 requests a second:
    ```bash
    ./k6 run --quiet tests/cache.js; echo "exit code: $?"
    ```
    ```
        ✓ 'p(99)<500' p(99)=17.27ms
        http_reqs......................: 4501   150.019744/s
    ```
    Nearly three times the real limit, because the cache answered.

12. Pitfall: testing from the same box. Run a 50/s test in terminal 1 and watch CPU in terminal 2.
    ```bash
    # terminal 1
    ./k6 run --quiet -e RATE=50 -e DURATION=30s tests/load.js
    ```
    ```bash
    # terminal 2, about 15 seconds later
    docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'
    ```
    In the video k6 used about 15 % CPU, the API sat at its 1-CPU limit, the database under 1 %.

## Common mistakes
- **Testing from the same box.** k6 and the API share the laptop, so results move with whatever else runs. Use separate
  machines for the load generator, and run each test a few times.
- **Cache-warm tests.** Always the same user, and the cache answers: you measure the cache, not the service.
- **No think time.** A closed-model VU without `sleep` hammers non-stop, so 100 VUs are not 100 students. Add sleeps or
  use arrival rates.
- **Ignoring the database.** Seven instances mean seven connection pools; Postgres allows 100 connections by default.
  Test the whole path and plan the database too.
- **Using the closed model for capacity questions.** It hides stalls; use `constant-arrival-rate` / `ramping-arrival-rate`.

## Clean up
```bash
docker compose down -v
docker image rm loadtest-lab/api:1.0
```

## Next
[M17-L04 · Chaos Engineering and Disaster Recovery](../m17-l04-chaos-engineering-and-disaster-recovery/)
