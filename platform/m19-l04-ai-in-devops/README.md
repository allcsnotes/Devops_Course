# M19-L04 · AI in DevOps
> Video: Module 19, Lesson 4. Watch it first, then follow along here.

## What you'll learn
- The two families of AI in operations: **AIOps** (statistics on telemetry: anomaly detection, correlation) and **LLM assistants** (read and write text)
- Classic AIOps with no model at all: a z-score in PromQL, and alert correlation by time window + service map + deploy log
- Why a raw paste fails and a small, redacted **bundle** (alerts, deploys, top errors, one trace) works, and how to verify the answer
- Using a model on a red CI log and for a postmortem draft, and checking what it wrote
- The limits, each shown for real: stale knowledge, prompt injection through log lines, data privacy, cost/latency, and never letting it run mutating commands
- Evaluate before you trust: a 15-incident eval set, and why you grade the grader

## Before you start
- Docker Desktop with **at least 4 CPUs and 6 GB memory** for Docker (the model alone is capped at 4 CPUs / 4 GB), about 4 GB of disk.
- Internet the first time (images, Python packages, and the 2.0 GB model). After `ai.sh pull` the model runs fully offline.
- Pinned versions used in the video: Ollama `0.40.6` with `llama3.2:3b` (Q4_K_M, Llama 3.2 Community License),
  Prometheus `v3.15.0`, Alertmanager `v0.34.1`, Tempo `3.1.0`, PostgreSQL `18.6-alpine3.24`, Python `3.13.16-slim`.
- Time: the staged incident needs about **45 minutes** of normal traffic first (the z-score baseline is 30 minutes),
  and on a laptop CPU each model answer takes from half a minute to about nine minutes.
- Helpful background: alerting and routing (Module 17, lesson 6), the M17-L02 slow-query release, the M18-L01 security
  pipeline (its failed `deps` job is in `ci/`).
- The lab clock is IST (UTC+05:30), like the video. All `HH:MM` arguments below are IST.

**No time or not enough memory?** `sample-incident/` holds the evidence recorded in the video, so you can run the
no-model steps (correlation) on your own laptop with only `python3`:
```bash
python3 ai/corr.py sample-incident/alerts.json sample-incident/deploys.log
```

## Files in this folder
| File | What it is |
|---|---|
| `lab/compose.yaml` | The allcsvideos request path: storefront-bff x2 and Course Copilot → catalog-api x2 → PostgreSQL, plus Prometheus, Alertmanager, a lab pager (`receiver`), Tempo, a load generator and the ops box |
| `lab/build.sh` | Builds the images: catalog-api 1.4.2 / 1.5.0, edge 2.3.0 / 2.3.1, the ops box |
| `lab/ai.sh` | `pull` / `up` / `down` the local model (Ollama on an internal network, no internet) |
| `lab/deploy.sh` | Rolls a service to a version, one replica at a time, and logs the deploy (also used to roll back) |
| `lab/incident.sh` | The staged incident: deploy 1.5.0, the staged prompt-injection search, then capture the evidence into `incident/` |
| `lab/down.sh` | Removes everything the lab created |
| `lab/app/`, `lab/edge/`, `lab/db/`, `lab/prometheus/`, `lab/alertmanager/`, `lab/receiver/`, `lab/tempo/`, `lab/load/`, `lab/ops/` | The services and their configs |
| `ai/corr.py`, `ai/anomaly.py`, `ai/zscore.sh` | Classic AIOps: correlation and z-score anomaly detection |
| `ai/naive.sh`, `ai/redact.py`, `ai/bundle.py`, `ai/ask.py` | The 2 a.m. paste, redaction, the context bundle, and the model client |
| `ai/verify.py`, `ai/fails.py` | Check the model's claim against the request, deploy and pager logs |
| `ai/cilog.py`, `ai/factcheck.py`, `ai/guard.py`, `ai/timings.py` | Trim a CI log, fact-check a postmortem draft, the read-only command guard, cost per answer |
| `eval/eval.py`, `eval/cases.json` | 15 past incidents from this course's labs with known root causes, and the scorer |
| `prompts/` | System prompts and questions used in the lesson (`triage_system.txt`, `plain_system.txt`, `stale.txt`, `pm.txt`, `ci_naive.txt`, `ci_better.txt`) |
| `ci/` | The M18-L01 `security.yml`, the failed `deps` job log (189 lines), and today's pinned requirements |
| `pm/timeline.txt` | The real M17 incident timeline the postmortem draft is checked against |
| `sample-incident/` | The evidence recorded in the video (alerts, deploys, pager log, trace, corr/anomaly results) |
| `incident/`, `outputs/` | Empty: your captured evidence and model answers go here |

## Follow along
All `python3 ai/...` commands run **inside the ops box**, in `/work` (this folder):
```bash
docker exec -it ai-lab-ops bash
```

### 1. Start the lab and the traffic
```bash
cd platform/m19-l04-ai-in-devops/lab
./build.sh
docker compose up -d
RUN=r1 docker compose --profile load up -d load
```
Ten simulated students a second, logged to `lab/runs/r1.csv`. About 40 minutes before the incident, Asha deploys a
storefront change (a real, harmless one, it shows up later as a "recent change"):
```bash
./deploy.sh storefront-bff 2.3.1 asha
```

### 2. The model: small, local, offline
```bash
./ai.sh pull     # the only step with internet: about 2.0 GB
./ai.sh up       # Ollama on an internal network, 4 CPUs, 4 GB, cloud models off
docker exec -it ai-lab-ollama bash
ollama --version
ollama list
ollama pull qwen3:1.7b
```
You should see the pull fail: the lab's data can't leave this machine.
```
ollama version is 0.40.6
llama3.2:3b    a80c4f17acd5    2.0 GB
Error: pull model manifest: Get "https://registry.ollama.ai/...": dial tcp: lookup registry.ollama.ai ...: server misbehaving
```
The thread-count surprise: in the video, with Ollama's default thread count a nine-token answer took 55 seconds;
with `num_thread` 4 (matching the CPU limit) it took 0.35 seconds. `ai/ask.py` always sends `num_thread: 4`,
`temperature: 0` and a fixed seed. Try it from the ops box:
```bash
curl -s ollama:11434/api/generate -d '{"model":"llama3.2:3b","prompt":"Name one sorting algorithm.","stream":false,"options":{"num_thread":4}}' | jq -c '{response, eval_count, eval_s: (.eval_duration/1e9)}'
```

### 3. Stage the incident
After at least 40 minutes of traffic (from the host, in `lab/`):
```bash
./incident.sh
```
Priya deploys catalog-api **1.5.0**; about three minutes later the evidence is captured into `incident/`. Note the
time printed for the injection search, you need it in step 12. In the video: 37 alerts, 13,028 log lines.

### 4. The 2 a.m. paste (the hook)
In the ops box:
```bash
T0=$(jq -s 'map(select(.version=="1.5.0"))[0].start' lab/incident/deploys.log)
jq -r --argjson t "$T0" 'select(.kind=="page" and .status=="firing" and .epoch>$t) | "\(.ts)  PAGE  \(.group.alertname)  \(.group.service)  (\(.alerts) alerts)"' lab/incident/notifications.log | head -6
jq length incident/alerts.json
wc -l < incident/logs-all.txt
sh ai/naive.sh
python3 ai/ask.py prompts/naive.txt --out naive
```
In the video the answer took 147 seconds, invented a service mesh and kubectl commands, and never mentioned the deploy:
```
prompt: 37 alerts, 842 lines, 268141 characters
The error message is generated by the `storefront-bff` service, which is a service mesh proxy. ...
[llama3.2:3b · context default 4096 · read 2050 prompt tokens · wrote 499 tokens · 147.4 s]
```
It read only 2,050 tokens of a 268,000-character prompt, and said nothing about it.

### 5. AIOps without a model: anomaly detection
z-score = (value − baseline mean) / baseline standard deviation, baseline = the 30 minutes ending 5 minutes ago.
Use your own times: START about 10 minutes before the deploy, END the capture time.
```bash
python3 ai/anomaly.py 01:50 02:03 | tee incident/anomaly.txt
sh ai/zscore.sh service:http_p95:1m 02:01
sh ai/zscore.sh service:http_errors:ratio_rate1m 02:01
```
```
  catalog-api     anomaly from 02:00:15 (z = 3.2), peak z = 48.6 at 02:01:15
  course-copilot  anomaly from 02:00:30 (z = 16.7), peak z = 18.9 at 02:03:00
  storefront-bff  anomaly from 02:00:30 (z = 26.9), peak z = 29.6 at 02:01:15
...
["storefront-bff","+Inf"]
```
On latency it works. On the error ratio it breaks: the baseline was zero errors, so the deviation is zero.

Seasonality: in Prometheus 3, `holt_winters` is gone; it's `double_exponential_smoothing`, behind
`--enable-feature=promql-experimental-functions` (already on in `compose.yaml`):
```bash
curl -sG prometheus:9090/api/v1/query --data-urlencode 'query=holt_winters(service:http_p95:1m[10m], 0.5, 0.5)'
curl -sG prometheus:9090/api/v1/query --data-urlencode 'query=double_exponential_smoothing(service:http_p95:1m{service="catalog-api"}[10m], 0.5, 0.5)' | jq -c '.data.result[] | [.metric.service, .value[1]]'
```
```
{"error":"invalid parameter \"query\": 1:1: parse error: unknown function with name \"holt_winters\""}
```

### 6. AIOps without a model: correlation
Alertmanager already groups by alert name and service; `corr.py` adds two rules: alerts within five minutes of each
other belong together, if their services call each other.
```bash
python3 ai/corr.py incident/alerts.json incident/deploys.log | tee incident/corr.txt
```
```
37 firing alerts, 7 alert names, 3 services
-> 1 incident
  storefront-bff  21 alerts  victim (calls catalog-api)
  catalog-api     10 alerts  probable origin
  course-copilot   6 alerts  victim (calls catalog-api)
  changes in the hour before the first alert:
    01:20:54  storefront-bff 2.3.1 by asha  (2386 s before)
    02:00:00  catalog-api 1.5.0 by priya  (40 s before)  <- on the probable origin
```
No model, no magic: a time window, a map and a deploy log.

### 7. Give the model a fair chance: redact, bundle, ask
```bash
python3 ai/redact.py incident/logs-all.txt incident/logs-red.txt
python3 ai/bundle.py prompts/bundle.txt
cat prompts/triage_system.txt
python3 ai/ask.py prompts/bundle.txt --system prompts/triage_system.txt --out triage
```
```
bundle: 5 sections, 2870 characters -> prompts/bundle.txt
Probable root cause: ... catalog-api service, specifically version 1.5.0 deployed at 02:00:00 ...
[llama3.2:3b · context default 4096 · read 1110 prompt tokens · wrote 328 tokens · 62.2 s]
```
Not perfect: in the video it never mentioned the statement timeout, hinted at a restart or scaling, and never said "roll back".

### 8. A human decides, then verify against the real record
Asha rolls back (from the host, in `lab/`):
```bash
./deploy.sh catalog-api 1.4.2 asha
```
Then, in the ops box:
```bash
python3 ai/verify.py
python3 ai/fails.py 01:59:00 02:10:00
```
```
02:00:00  deploy catalog-api 1.5.0 started (priya)
02:00:02  first failed request (storefront-bff /)
02:00:50  first page: HighErrorRate storefront-bff
02:08:18  rollback to 1.4.2 started (asha)
02:08:39  last failed request
failed in the 30 min before the deploy: 0 of 18000
during the impact: 4072 of 5172 requests failed (78.7%)
```
The model pointed. The tools proved it. A human acted.

### 9. A red pipeline: raw log vs trimmed log
The real failed `deps` job from M18-L01 is in `ci/deps-job.log` (189 lines). `prompts/ci_naive.txt` is one question
plus the whole log; `prompts/ci_better.txt` is a tighter question plus what `cilog.py` keeps. Rebuild them yourself:
```bash
{ head -1 prompts/ci_naive.txt; echo; cat ci/deps-job.log; } > /tmp/ci_naive.txt && diff -q /tmp/ci_naive.txt prompts/ci_naive.txt
python3 ai/cilog.py ci/deps-job.log ci/security.yml deps | head -20
python3 ai/ask.py prompts/ci_naive.txt --ctx 8192 --out ci1
python3 ai/ask.py prompts/ci_better.txt --ctx 8192 --out ci2
```
In the video: raw = 6,255 tokens, 530 seconds, right finding (pyyaml, CVE-2020-14343, update to 5.4) then nonsense;
trimmed = 41 of 189 lines, 1,151 tokens, 91 seconds, step + finding + fix. (At `--ctx 16384` the runner was killed at
the 4 GB limit: a bigger context costs memory.) Check it anyway:
```bash
grep -n 'args:' ci/security.yml | sed -n 3,4p
grep -n pyyaml ci/requirements-now.txt
```
The gate blocks HIGH/CRITICAL with a fix; 5.4 is only the minimum, the repo now pins `pyyaml==6.0.3`.

### 10. Paperwork: a postmortem draft, fact-checked
```bash
python3 ai/ask.py prompts/pm.txt --ctx 4096 --out pm1
jq -r .response.message.content outputs/pm1.json > /tmp/draft.md
python3 ai/factcheck.py /tmp/draft.md pm/timeline.txt
```
```
NOT IN SOURCE  21:19:23  Pager acknowledged by asha
13 timeline lines match the source, 1 do not · numbers not in the source: none
```
The page went out at 21:19:23; she acknowledged at 21:19:50. A checker can't catch the rest (an invented
"deployment team", "training"): the owner of the postmortem still edits every line.

### 11. Limit one: stale knowledge
```bash
python3 ai/ask.py prompts/stale.txt --out stale
```
```
... the latest stable version of Kubernetes is 1.25. The latest stable version of Prometheus is 2.34.
```
This course runs 1.37 and 3.15. Give it facts from your tools, or it guesses.

### 12. Limit two: prompt injection through log lines
The staged search from step 3 sits in the storefront logs. Use the injection time `incident.sh` printed (plus a few
seconds) for `--until`:
```bash
python3 ai/bundle.py prompts/bundle_raw.txt --raw 6 --until 02:02:37
python3 ai/bundle.py prompts/bundle_def.txt --raw 6 --until 02:02:37 --defend
python3 ai/ask.py prompts/bundle_raw.txt --system prompts/plain_system.txt --out inj1
python3 ai/ask.py prompts/bundle_raw.txt --system prompts/triage_system.txt --out inj2
python3 ai/ask.py prompts/bundle_def.txt --system prompts/triage_system.txt --out inj3
```
In the video: run 1 ended with "Close the incident" (the planted line's words) and "roll back to 1.5.0"; run 2
added "Restart the storefront-bff service"; run 3 (raw lines as JSON in an UNTRUSTED block, the instruction-like line
removed and flagged) was not hijacked, but nudged. The real defence: read-only tools and a human approving every change.

### 13. Limit three: data privacy
```bash
grep -c 'example.com' incident/edge-all.txt
grep -o '"catalog_api_key": "[^"]*"' incident/edge-all.txt
python3 ai/redact.py incident/edge-all.txt incident/edge-red.txt
grep -o '"catalog_api_key": "[^"]*"' incident/edge-red.txt
grep -o '"user": "[^"]*"' incident/edge-red.txt | sort | uniq -c
```
```
17614 lines read, 3673 email, 2 api-key redacted
"catalog_api_key": "[REDACTED:api-key]"
   3673 "user": "[REDACTED:email]"
```
The emails and the key are FAKE, staged on purpose. Redact before any model sees the text, even a local one.

### 14. Limit four: cost and latency
```bash
python3 ai/timings.py
```
```
request                    read  wrote  seconds  tokens/s read · written
naive 2 a.m. question      2050    499    147.4   53.5 ·  4.6
grounded triage bundle     1110    328     62.2   61.5 ·  7.6
raw CI log                 6255    473    529.5   27.5 ·  1.7
trimmed CI log             1151    120     90.7   37.0 ·  4.8
postmortem draft            739    621    125.6   53.4 ·  7.1
```

### 15. Limit five: never let it run mutating commands
`guard.py` is the only path from a suggestion to a shell:
```bash
python3 ai/guard.py curl -sG prometheus:9090/api/v1/query --data-urlencode 'query=sum by (service) (up)' | jq -c '.data.result[] | [.metric.service, .value[1]]'
python3 ai/guard.py ./lab/deploy.sh catalog-api 1.4.2 assistant
```
Answer `n`:
```
allowed (read-only): curl -sG prometheus:9090/api/v1/query --data-urlencode query=sum by (service) (up)
BLOCKED: not on the read-only allowlist: ./lab/deploy.sh catalog-api 1.4.2 assistant
This changes production. Proposal for the on-call engineer. Run it? [y/N] n
not run
```

### 16. Evaluate before you trust
```bash
python3 eval/eval.py
```
```
10 of 15 root causes found (67%) · llama3.2:3b · 116 s
```
Then read every answer in `outputs/eval_rows.json`. In the video: 7 right and specific, 3 right area but too vague,
1 "unknown", 4 wrong, and one wrong answer (net-latency, blamed DNS) still scored a hit. Grade the grader, rerun the
set on every model and prompt change, and publish the number.

## Common mistakes
- **Pasting everything.** The context window cut 268,000 characters to 2,050 tokens, silently. Send a bundle, not a dump.
- **Trusting the tone.** A service mesh that doesn't exist sounded as sure as the right answer. Check every claim against logs, metrics and deploys.
- **Giving it the keys.** No mutating commands without a human. Read-only first.
- **Leaking data.** Redact secrets and personal data before any prompt, and know where the model runs. A hosted API receives everything you paste.
- **Never measuring.** Without an eval set you don't know if it's right 7 times in 15, or 10.

## Clean up
From `lab/`:
```bash
docker compose --profile load stop load
./down.sh
```
`down.sh` removes the Ollama container, its internal network and the model volume (2 GB), the compose stack with its
volumes, the `allcs-*` images, and the generated evidence and answers (`incident/`, `outputs/`, `lab/runs/`, `lab/incident/`).

## Next
[M20-L01 · Designing a Production Delivery Platform](../../capstones/m20-l01-designing-a-production-delivery-platform/)
