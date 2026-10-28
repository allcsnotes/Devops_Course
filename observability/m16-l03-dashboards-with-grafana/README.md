# M16-L03 · Dashboards with Grafana
> Video: Module 16, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- Every dashboard has one audience and one question; on-call gets RED at the top left, saturation and host USE below.
- How Grafana works: a viewer over data sources (Prometheus here), with proxy access; a dashboard is one JSON document.
- Dashboards as code: data sources and dashboards provisioned from files in Git, with a pinned data source UID.
- Building the service board: `$__rate_interval`, units, thresholds, percentiles, a heatmap, variables, deploy annotations.
- Reading a staged incident in five seconds - and why the "everything" board can't.
- Pitfalls: averages, missing units, too many panels, no owner, unused boards, unpinned data source UIDs.

## Before you start
- Docker Desktop (Compose v2), `git`, `curl`, `jq`; a browser.
- The course app copy at the repo root ([`allcsvideos/`](../../allcsvideos/)) for the Copilot service.
- [M16-L02](../m16-l02-metrics-with-prometheus/) (PromQL, histograms, `pq`).

## Files in this folder
| File | What it is |
|---|---|
| `lab/compose.yaml` | Project `m16-dashboards`: `db`, `api-1` + `api-2` (lab API), `copilot`, node exporter v1.12.1, Prometheus v3.15.0 (port 9090), Grafana 13.2.4 (port 3000, FAKE admin password), `loadgen` (profile `load`) |
| `lab/api/`, `lab/db/` | The lab API from M16-L01 (now with `APP_VERSION` and `DEFAULT_SORT`, and `http_requests_in_flight`) and its catalog database |
| `changes/copilot/app/main.py`, `changes/copilot/requirements.txt` | Copilot using the team's shared `http_*` metric names (`http_requests_total{route,status}`, `http_requests_in_flight`, `http_request_duration_seconds`) |
| `lab/prometheus/prometheus.yml` | Scrapes `node`, `api` (two targets), `copilot` every 15 s |
| `lab/grafana/provisioning/datasources/prometheus.yaml` | The Prometheus data source with pinned uid `prom-lab` and `timeInterval: 15s` |
| `lab/grafana/provisioning/dashboards/allcsvideos.yaml` | Dashboard provider: folder `allcsvideos`, `allowUiUpdates: false`, re-read every 10 s |
| `lab/grafana/dashboards/service-red.json` | The on-call board (uid `allcs-red`): RED stats, percentiles, by status, heatmap, saturation, host USE; variables `service` and `instance`; deploy annotations |
| `lab/grafana/dashboards/everything.json` | Last week's "everything" board: 30 panels, defaults left as they are |
| `lab/loadgen/loadgen.py` | 8 API requests/s (2% popular sort) and 2 Copilot questions/s, 2 s timeout |
| `lab/make-token.sh` | Creates service account `deploy-bot` (Editor) and writes its token to `.env` (git-ignored) |
| `lab/deploy.sh` | `deploy.sh VERSION [SORT]`: roll both API copies, then POST a `deploy` annotation to Grafana |
| `lab/pq.sh` | The `pq` PromQL helper from M16-L02 (port 9090) |

## Follow along

1. Build the lab folder and make it a Git repository (dashboards are code):
   ```bash
   LESSON=$PWD                                   # run from this lesson's folder
   mkdir -p ~/m16-dashboards && cp -R lab/. ~/m16-dashboards/
   cp -R ../../allcsvideos/copilot ~/m16-dashboards/copilot
   cp -R changes/copilot/. ~/m16-dashboards/copilot/
   cd ~/m16-dashboards
   git init -q -b main && git add -A && git commit -qm "dashboards lab"
   docker compose --profile load up -d --build
   ```

2. What is provisioned, and is it up?
   ```bash
   tree -a -I .git grafana
   docker compose ps --format "table {{.Service}}\t{{.Image}}\t{{.Status}}"
   curl -s localhost:3000/api/health | jq
   docker compose logs --no-log-prefix grafana | grep -oE 'logger=provisioning.(datasources|dashboard) .*' | sed -E 's/ t=[^ ]+ level=info//'
   curl -s -u admin:fake-admin-pass-123 localhost:3000/api/datasources/uid/prom-lab | jq "{name, uid, type, url, access}"
   curl -s -u admin:fake-admin-pass-123 "localhost:3000/api/search?type=dash-db" | jq -r ".[] | .uid + \"   \" + .title"
   ```
   ```
   "version": "13.2.4"
   logger=provisioning.datasources msg="inserting datasource from configuration" name=Prometheus uid=prom-lab
   allcs-everything   allcsvideos · everything
   allcs-red   allcsvideos · service health (RED)
   ```
   Nobody clicked anything.

3. Read the board's JSON before you open it: `uid`, `description` (owner, audience, question), `time` (last 30 min),
   `refresh` (10 s), the `service` / `instance` variables, the queries with `$__rate_interval`, the units and
   thresholds, and the `deploy` annotation.
   ```bash
   jq '{uid, title, description, time, refresh, vars: [.templating.list[].name], panels: [.panels[].title]}' grafana/dashboards/service-red.json
   ```

4. Open http://localhost:3000 (user `admin`, password `fake-admin-pass-123`) -> Dashboards -> folder `allcsvideos` ->
   **allcsvideos · service health (RED)**. Top left, the calm state: about 8.0 req/s, 0.00 % errors, p95 ~5 ms,
   p99 ~200 ms, all green. Switch `service` to `copilot`: ~2 req/s, errors ~3 % (amber, the staged fault rate),
   p95 ~460 ms. The pool panel says there is no DB pool in that service. Back on `api`, try `instance`.

5. Change a threshold through Git: Rahul wants p95 amber at 250 ms, not 300. Edit
   `grafana/dashboards/service-red.json`: set `"version": 2`, the p95 panel's amber step `"value": 0.3` -> `0.25`, and
   its description "Amber at 300 ms" -> "Amber at 250 ms". Then:
   ```bash
   git diff -U0 grafana/dashboards/service-red.json
   git commit -qam "dashboards: p95 amber at 250 ms (team target)"
   sleep 15; curl -s -u admin:fake-admin-pass-123 localhost:3000/api/dashboards/uid/allcs-red | jq -c "{version: .dashboard.version, p95_amber: .dashboard.panels[3].fieldConfig.defaults.thresholds.steps[1].value, provisioned: .meta.provisioned}"
   ```
   `{"version":...,"p95_amber":0.25,"provisioned":true}` - Grafana re-read the file, no restart, no clicking.

6. The staged incident: v1.1 sorts the course list by popularity by default (a 2-million-row scan per request).
   First create the deploy-bot token, then deploy:
   ```bash
   ./make-token.sh
   set -a; . ./.env; set +a
   cat deploy.sh
   ./deploy.sh 1.1 popular
   ```
   ```
    ✔ Container m16-dashboards-api-1-1 Started
    ✔ Container m16-dashboards-api-2-1 Started
   {"id":1,"message":"Annotation added"}
   ```

7. Wait about four minutes and look at the board. Five seconds, top left: errors 100 % (red), p95 ~2.5 s, p99 ~4.4 s,
   traffic still 8/s. The dashed deploy line shows *when*; the heatmap and the by-status panel show *what*
   (200s gone, 500s and 503s); saturation shows *where* (in-flight ~8 per copy, DB pool 100 %), while host CPU is fine.
   The numbers behind it:
   ```bash
   source pq.sh
   pq 'histogram_quantile(0.50, sum by (le) (rate(http_request_duration_seconds_bucket{job="api"}[2m])))'
   pq 'sum(rate(http_request_duration_seconds_sum{job="api"}[2m])) / sum(rate(http_request_duration_seconds_count{job="api"}[2m]))'
   pq 'histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket{job="api"}[2m])))'
   ```

8. Roll back and list the deploy annotations:
   ```bash
   ./deploy.sh 1.0
   curl -s -H "Authorization: Bearer $GRAFANA_TOKEN" "localhost:3000/api/annotations?tags=deploy" | jq -r ".[] | (.time / 1000 | strflocaltime(\"%H:%M:%S\")) + \"  \" + .text"
   ```
   ```
   18:43:39  api 1.0 deployed (sort=id)
   18:38:59  api 1.1 deployed (sort=popular)
   ```
   A few minutes later the board is green again, with two dashed lines bracketing the incident. Now open
   **allcsvideos · everything** at its default 6 hours: the incident is a sliver among 30 unlabelled panels.

9. Pitfall 1 - averages, on a calm minute:
   ```bash
   pq 'histogram_quantile(0.50, sum by (le) (rate(http_request_duration_seconds_bucket{job="api"}[2m])))'
   pq 'sum(rate(http_request_duration_seconds_sum{job="api"}[2m])) / sum(rate(http_request_duration_seconds_count{job="api"}[2m]))'
   pq 'histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket{job="api"}[2m])))'
   ```
   In the video: p50 2.6 ms, mean 6.8 ms, p99 244 ms.

10. A community dashboard: Node Exporter Full (grafana.com ID 1860, revision 45), imported through the API:
    ```bash
    curl -sL https://grafana.com/api/dashboards/1860/revisions/45/download -o community/node-exporter-full.json
    jq -r '.title, ([.. | objects | select(.gridPos? and .type != "row")] | length | "\(.) panels"), ([.templating.list[] | .name + " (" + .type + ")"] | join(", "))' community/node-exporter-full.json
    jq '{dashboard: ., overwrite: true}' community/node-exporter-full.json | curl -s -u admin:fake-admin-pass-123 -H 'Content-Type: application/json' localhost:3000/api/dashboards/db -d @- | jq -c '{status, uid, url}'
    ```
    `124 panels`, a `ds_prometheus (datasource)` variable instead of a fixed UID, `"status":"success"`. Open it:
    Root FS Used says N/A on Docker Desktop (no filesystem mounted at `/` in its VM). Learn from it, then copy only
    the panels you need into your own board.

11. Pitfall 6 - an unpinned data source UID. Copy the board as if it came from another Grafana whose Prometheus had
    a different UID:
    ```bash
    sed -e 's/prom-lab/P1809F7CD0C75ACF3/g' -e 's/"uid": "allcs-red"/"uid": "allcs-red-copy"/' -e 's/service health (RED)/service health (RED) copy/' grafana/dashboards/service-red.json > grafana/dashboards/service-red-copy.json
    grep -c "P1809F7CD0C75ACF3" grafana/dashboards/service-red-copy.json
    curl -s -u admin:fake-admin-pass-123 localhost:3000/api/datasources | jq -r ".[] | .name + \"  uid=\" + .uid"
    ```
    Open the copy: every panel shows `Datasource P1809F7CD0C75ACF3 was not found`, and the stats say No data, in
    green. Delete it:
    ```bash
    rm grafana/dashboards/service-red-copy.json && git status --short grafana
    ```

## Common mistakes
- Graphing averages: a 6.8 ms mean next to a 244 ms p99. Graph percentiles from histograms.
- No units: `1792517943` is a boot time in Unix seconds. Set seconds, bytes, percent, req/s or a date.
- Too many panels: 30 queries per refresh per viewer, and nowhere for the eye to land. The service board has 13.
- No owner: put owner, audience and question in the description.
- Boards nobody opens: review them, delete the ones that answer no one's question.
- Unpinned data source UIDs: pin the UID in provisioning (`prom-lab`) or use a data source variable.
- Refreshing faster than the scrape interval: every refresh reruns every query for every viewer.
- Clicking dashboards together in the UI only: no review, no history, gone with the volume. Provision from Git.

## Clean up
```bash
cd ~/m16-dashboards
docker compose --profile load down -v --rmi local
cd ~ && rm -rf ~/m16-dashboards
```

## Next
[M16-L04 · Logs](../m16-l04-logs/) - structured logging, Loki and the ELK stack, finding one request in a million lines.
