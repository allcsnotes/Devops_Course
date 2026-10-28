# M17-L01 · SLIs, SLOs and Error Budgets
> Video: Module 17, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- An **SLI** is good events divided by valid events, picked from the user's journey and measured as close to the user as you can.
- An **SLO** is a target for an SLI over a rolling window (here: 99.9 % of course-list requests succeed over 30 days).
- The **error budget** (100 % minus the SLO) counted in requests, and an **error budget policy** agreed in advance.
- **Burn rate** and the multiwindow, multi-burn-rate alerts from the SRE Workbook (14.4x over 1 h + 5 min, 6x over 6 h + 30 min).
- Generating the same rules from a short spec with **Sloth**, and the pitfall of measuring only at the server.

## Before you start
- Docker Desktop (Compose v2), `curl`, `jq` and `python3` on your laptop.
- The ideas from Module 16 (Prometheus, Grafana, alerting). You don't need its files: this folder is a self-contained lab.
- Free ports 3000 (Grafana) and 9090 (Prometheus).
- Images used (pinned): `postgres:18.6-alpine3.24`, `python:3.13.16-slim`, `python:3.13.16-alpine3.23`,
  `prom/prometheus:v3.15.0`, `grafana/grafana:13.2.4`, `ghcr.io/slok/sloth:v0.16.0`.

## Files in this folder
| File | What it is |
|---|---|
| `lab/compose.yaml` | The lab: catalog API + Postgres, `loadgen` (students at 10 requests/s), Prometheus, Grafana |
| `lab/api/` | The catalog API. `FAULT_RATE` makes a share of requests fail with 500 (the staged bug in 1.1) |
| `lab/loadgen/loadgen.py` | Simulated students; also counts errors from the client's side (`client_requests_total`) |
| `lab/history/gen_history.py` | Writes 30 days of **synthetic** history (with two incidents) for `promtool` to backfill |
| `lab/prometheus/slo-rules.yml` | SLI recording rules for 5m ... 30d, availability, budget left, burn rates |
| `lab/prometheus/slo-alerts.yml` | The page and ticket burn-rate alerts (`CatalogErrorBudgetBurn`) |
| `lab/grafana/` | Data source + the provisioned SLO dashboard (`allcsvideos · catalog API SLO`) |
| `lab/docs/error-budget-policy.md` | The allcsvideos error budget policy, kept in Git next to the code |
| `lab/sloth/catalog-slo.yml` | The same SLO as a Sloth spec; `lab/sloth/rules.yml` is what Sloth generated |
| `lab/pq.sh` | Shell helpers: `pq 'PromQL'`, `alerts`, `slo` |
| `lab/deploy.sh` | Roll the API to a version (and fault rate), then add a Grafana annotation |
| `lab/token.sh` | Creates the `deploy-bot` Grafana service account token that `deploy.sh` needs |

## Follow along
1. Go into the lab and load the helpers.
   ```bash
   cd lab
   . ./pq.sh
   ```

2. Generate the 30-day history. An SLO window is 30 days and nobody waits that long, so the history is generated
   (and says so). It also prints the two `@` timestamps you'll use in step 7.
   ```bash
   python3 history/gen_history.py $(date +%s) history/history.om
   ```
   You should see something like:
   ```
   wrote history/history.om from 2026-09-21 15:22:00+05:30 to 2026-10-21 21:22:00+05:30 requests 26166128 errors 19333
   ```

3. Turn the file into real Prometheus blocks with `promtool`, before Prometheus starts.
   ```bash
   docker compose run --rm --no-deps --entrypoint promtool prometheus tsdb create-blocks-from openmetrics --max-block-duration=24h /history/history.om /prometheus
   ```
   You should see a table of about 41 blocks, each with `NUM SERIES 16`.

4. Start the lab and check the five containers.
   ```bash
   docker compose up -d --build
   docker compose ps --format "table {{.Service}}\t{{.Image}}\t{{.Status}}"
   ```
   ```
   SERVICE      IMAGE                      STATUS
   api          slo-lab/api:1.0            Up 8 seconds
   db           postgres:18.6-alpine3.24   Up 13 seconds (healthy)
   grafana      grafana/grafana:13.2.4     Up 13 seconds
   loadgen      python:3.13.16-slim        Up 13 seconds
   prometheus   prom/prometheus:v3.15.0    Up 13 seconds
   ```

5. Read `prometheus/slo-rules.yml` and `prometheus/slo-alerts.yml`, then let `promtool` check them.
   ```bash
   docker compose exec prometheus promtool check rules /etc/prometheus/slo-rules.yml /etc/prometheus/slo-alerts.yml
   ```
   ```
   Checking /etc/prometheus/slo-rules.yml
     SUCCESS: 16 rules found

   Checking /etc/prometheus/slo-alerts.yml
     SUCCESS: 2 rules found
   ```

6. Ask Prometheus for the SLO numbers.
   ```bash
   pq 'job:slo_availability:ratio_rate30d'
   pq 'job:slo_requests:increase30d'
   pq 'job:slo_errors:increase30d'
   pq 'job:slo_error_budget:remaining_ratio30d'
   pq 'job:slo_burn_rate:5m'
   ```
   In the video (your numbers will be close):
   ```
   __name__=job:slo_availability:ratio_rate30d job=api   0.9992543515813943
   __name__=job:slo_requests:increase30d job=api   25904170.76894189
   __name__=job:slo_errors:increase30d job=api   19315.403969154773
   __name__=job:slo_error_budget:remaining_ratio30d job=api   0.2543515813942525
   __name__=job:slo_burn_rate:5m job=api   0
   ```
   Availability 99.925 %, SLO met, 25.4 % of the budget left.

7. Look at each incident hour with `@` (a fixed evaluation time). Use the two timestamps step 2 printed:
   ```bash
   pq 'sum(increase(http_requests_total{job="api",status=~"5.."}[1h] @ <FIRST_TIMESTAMP>))'
   pq 'sum(increase(http_requests_total{job="api",status=~"5.."}[1h] @ <SECOND_TIMESTAMP>))'
   ```
   About 14,483 errors for the October 6 migration lock (56 % of the budget) and 3,852 for the October 14 bad deploy.

8. Open Grafana at http://localhost:3000 (user `admin`, password `fake-admin-pass-123`, a fake lab password), folder
   `allcsvideos`, dashboard **allcsvideos · catalog API SLO**: availability, budget left, bad requests left, two burn
   rates and the page alert on top; burn rate over time (log scale, lines at 6 and 14.4) and bad requests per hour below.

9. Read the policy in `docs/error-budget-policy.md`. With 25.4 % left (above the 25 % line), Priya ships.

10. Create the deploy-bot token, then ship version 1.1 with its staged bug (1 request in 10 fails with a 500).
    ```bash
    export GRAFANA_TOKEN=$(./token.sh)
    ./deploy.sh 1.1 0.1
    ```
    ```
     ✔ Container slo-lab-api-1 Started    1.5s
    {"id":1,"message":"Annotation added"}
    ```

11. Watch the burn rates. Run `slo` every minute or so; the 5-minute burn rate jumps at once, the 1-hour one climbs slowly.
    ```bash
    slo
    alerts
    ```
    About 3 minutes in:
    ```
    21:39:26
      job:slo_burn_rate:5m                     64.830
      job:slo_burn_rate:1h                     4.4681
    ```
    About 9 minutes in, both windows are over 14.4 and the page fires:
    ```
    CatalogErrorBudgetBurn  severity=page  firing  since 21:45:25
    21:45:31
      job:slo_burn_rate:5m                     113.33
      job:slo_burn_rate:1h                     15.040
      job:slo_burn_rate:6h                     2.3782
      job:slo_error_budget:remaining_ratio30d  0.2310
    ```
    The alert is also on http://localhost:9090/alerts.

12. Roll back, then keep watching.
    ```bash
    ./deploy.sh 1.0
    slo
    alerts
    ```
    About 4.5 minutes after the rollback the 5-minute window drops under the line and `alerts` prints nothing, while
    the 1-hour burn rate is still around 20:
    ```
    21:52:59
      job:slo_burn_rate:5m                     10.035
      job:slo_burn_rate:1h                     20.243
    ```
    That is why every long window has a short one. Ten minutes later, budget left is about 22.4 %: under 25 %, so by the
    policy the search goes out again with the bug fixed, behind a canary, with a rollback plan.

13. Generate the same rules with Sloth from `sloth/catalog-slo.yml`.
    ```bash
    docker run --rm -v ./sloth:/w ghcr.io/slok/sloth:v0.16.0 generate -i /w/catalog-slo.yml -o /w/rules.yml --no-log
    grep -c "record:" sloth/rules.yml
    grep -o "rate[0-9]*[mhd]{.*> ([0-9.]* \*" sloth/rules.yml | sed "s/{.*>/ >/"
    ```
    ```
    15
    rate5m > (14.4 *
    rate1h > (14.4 *
    rate30m > (6 *
    rate6h > (6 *
    rate2h > (3 *
    rate1d > (3 *
    rate6h > (1 *
    rate3d > (1 *
    ```

14. Pitfall: measuring at the server, not the user. Stop the API for two minutes, then compare both sides.
    ```bash
    docker compose stop api
    # wait 2 minutes
    pq 'job:slo_errors_per_request:ratio_rate5m'
    pq 'up{job="api"}'
    pq 'sum(rate(client_requests_total{result="error"}[5m])) / sum(rate(client_requests_total[5m]))'
    alerts
    docker compose start api
    ```
    ```
    __name__=job:slo_errors_per_request:ratio_rate5m job=api   0
    __name__=up instance=api:8080 job=api   0
       0.40070175438596495
    ```
    The server's SLI says 0 errors and no page fires, but 40 % of the students' requests failed.

## Common mistakes
- **Measuring only at the server.** Requests that never reach it are never counted. Measure at the load balancer or
  client too, and keep a plain `up == 0` alert for when nothing answers at all.
- **A 100 % target.** The budget is zero, every deploy is forbidden, and the burn rate divides by zero.
- **Too many SLOs.** Twenty per service and nobody watches any. Start with one or two per user journey.
- **SLOs nobody owns.** Every SLO names a team, and the policy says what that team does when the budget runs low.
- **Alerting on raw error ratio.** Over 5 minutes it pages on every blip; over 30 days it fires after the budget is gone.

## Clean up
```bash
docker compose down -v
docker image rm slo-lab/api:1.0 slo-lab/api:1.1
rm -f history/history.om
```

## Next
[M17-L02 · Incident Response](../m17-l02-incident-response/)
