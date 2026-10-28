# M21-L03 · The Scenario Round
> Video: Module 21, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- How to answer "the pods keep restarting" with evidence: probe events, exit code 137, and a test under real load
- Why the restarts were only the messenger, and the real cause was capacity
- The twist "every pod in the namespace is crashing": look for what the pods share
- How to answer "deploys are slow": measure every stage first, then fix the biggest one
- The full on-call flow for "the site is down at 2 a.m.": acknowledge, severity, comms, roll back, verify, postmortem
- Weak versus strong answers, the follow-ups interviewers ask, and an example scoring rubric

## Before you start
- Docker Desktop (with the buildx plugin), about 4 GB of free memory for the cluster and 2 GB for the incident lab
- kind v0.33.0 and kubectl v1.37.1 (the cluster node image is pinned to `kindest/node:v1.37.0` by digest)
- `jq`, `curl` and `python3` on your laptop (for scenario 3)
- You should know the nine steps from [M21-L01](../m21-l01-how-devops-interviews-work/), question 21 from
  [M21-L02](../m21-l02-the-60-most-asked-devops-and-sre-questions/questions.md), and the incident lab from
  [M17-L02](../../observability/m17-l02-incident-response/) (scenario 3 reuses it).

Everything runs on your laptop. Nothing costs money. The faults are staged on purpose, as in the video.
The lab containers keep India time (`TZ=IST-5:30`), like the video, so their timestamps may differ from your clock.

## Files in this folder
| File | What it is |
|---|---|
| `lab/up.sh cluster` | Builds the catalog image, creates the kind cluster `scenarios`, deploys namespaces `allcs` (catalog, search, thumbs) and `lab` (users, debug pod), creates the BuildKit builder `ci-builder` and deploys `catalog-api:1.5.0` in namespace `shop` |
| `lab/up.sh incident` | Builds `catalog-api:1.4.2` and `1.5.0`, starts the incident lab with Docker Compose |
| `lab/down.sh` | Removes everything this lesson created |
| `k8s/app/app.py` | Scenario 1 catalog app: Python standard library, ONE worker. `HEALTH_PORT` turns on a separate health thread (the fix) |
| `k8s/app/traffic.py`, `k8s/app/probe.py` | The users (open-model load, 2 s client timeout) and a one-shot timing probe |
| `k8s/manifests/` | Namespaces, `catalog` (2 replicas, probes on the worker port, 1 s timeout), `search`, `thumbs` |
| `k8s/fixed/10-catalog.yaml` | The fixed catalog: probes on the health thread, port 8081 |
| `k8s/limitrange.yaml` | Twist 2, staged: a namespace default memory limit of 32Mi |
| `k8s/users.sh`, `k8s/traffic.yaml`, `k8s/debug.yaml` | Start the traffic pod (`./users.sh RATE SECONDS`), its manifest, and a debug pod |
| `pipeline/catalog-api/` | Scenario 2 repo: `app.py`, `pricing.py`, tests (staged 4 s waits), the slow `Dockerfile`, `pipeline.sh` (every stage timed) |
| `pipeline/shop.yaml` | The slow rollout: maxSurge 1, readiness after a 20 s delay, every 10 s |
| `pipeline/fixes/` | The fixed `Dockerfile` (requirements first) and `shop.yaml` (maxSurge 2, readiness every 2 s) |
| `incident/` | Scenario 3 lab: `compose.yaml` (API, PostgreSQL, Prometheus, Alertmanager, lab pager, status page, Grafana), `deploy.sh`, `inc.sh`, `status.sh`, `timeline.py` |
| `incident/runs/r2*` | The real logs from the video's run, so `python3 timeline.py r2` works without running the lab |

## Follow along

### Scenario 1: "The catalog pods keep restarting"

1. Start the cluster lab (takes a few minutes the first time):
   ```bash
   cd interview/m21-l03-the-scenario-round
   ./lab/up.sh cluster
   cd k8s
   kubectl get pods
   ```
   You should see two `catalog` pods, one `search` and one `thumbs`, all `1/1 Running`.

2. **Clarify and test the idle state.** Time the health check with no load:
   ```bash
   kubectl -n lab exec debug -- python /load/probe.py
   ```
   ```
   03:36:26 http://catalog.allcs/healthz -> 200 in 0.020 s
   ```

3. **Start the staged peak**, 50 requests a second for 150 seconds, and time the health check under load about 25 s later:
   ```bash
   ./users.sh 50 150
   kubectl -n lab exec debug -- python /load/probe.py /healthz 5
   ```
   ```
   03:37:01 http://catalog.allcs/healthz -> 200 in 4.034 s
   03:37:09 http://catalog.allcs/healthz -> 200 in 5.662 s
   ```
   The probe gives up after 1 second.

4. **Observe** (about 80 s after the start). Use one of your own catalog pod names:
   ```bash
   kubectl get pods
   kubectl describe pod <catalog-pod>
   kubectl logs <catalog-pod> --previous | tail -5
   ```
   You should see restarts only on `catalog`, and in `describe`:
   ```
       Last State:     Terminated
         Reason:       Error
         Exit Code:    137
       Liveness:   http-get http://:http/healthz delay=0s timeout=1s period=5s successThreshold=1 failureThreshold=3
     Normal   Killing    56s   kubelet  ... Container api failed liveness probe, will be restarted
     Warning  Unhealthy  1s (x5 over 66s)  kubelet  ... Liveness probe failed: ... context deadline exceeded
   ```
   Exit 137 with reason `Error`, not `OOMKilled`: the kubelet killed it because the health check was too slow. The
   previous logs show it serving up to 237 requests every 10 s, then nothing - no crash, no traceback. Why 137 and not 143?
   Python runs as PID 1 and ignores SIGTERM, so it is killed after the 30 s grace period.

5. **Measure the user impact** after the run (about 165 s after the start):
   ```bash
   kubectl -n lab logs traffic
   ```
   The first 10 s are fine, then between half and nearly all requests fail (about two thirds over the whole peak, 4,952 of 7,500 in the video).

6. **Mitigate first: more capacity.** Restart the catalog pods for a clean run, scale to 3, and repeat steps 3-5:
   ```bash
   kubectl scale deploy/catalog --replicas=3
   kubectl rollout status deploy/catalog
   kubectl delete pods -l app=catalog --wait && kubectl rollout status deploy/catalog
   ./users.sh 50 150
   ```
   Video result: 7,500 requests, 0 failed, 0 restarts.

7. **Fix the probe, alone.** The fixed manifest moves the probes to a health thread on port 8081 that fails only if one request is
   stuck for more than 10 s. It also sets replicas back to 2:
   ```bash
   kubectl apply -f fixed/10-catalog.yaml
   kubectl rollout status deploy/catalog
   ./users.sh 50 150
   ```
   Video result: 0 restarts, but 3,477 of 7,500 requests still failed. The restarts were the messenger; two one-worker pods
   can't serve 50 requests a second.

8. **Verify: fixed probe and three replicas**, same peak:
   ```bash
   kubectl scale deploy/catalog --replicas=3
   kubectl rollout status deploy/catalog
   ./users.sh 50 150
   kubectl -n lab logs traffic | tail -5
   ```
   ```
   03:47:17 sent=250 ok=250 failed=0 p95=109ms
   03:47:22 sent=249 ok=249 failed=0 p95=136ms
   ```
   Video result: 7,498 requests, 0 failed, 0 restarts, p95 mostly between 80 and 150 ms.

### Twist: "What if it's every pod in the namespace?"

9. Measure peak memory first, then stage the new namespace defaults and recreate every pod (a stand-in for a node drain):
   ```bash
   for d in catalog thumbs search; do echo "$d: $(kubectl exec deploy/$d -- cat /sys/fs/cgroup/memory.peak) bytes peak"; done
   kubectl apply -f limitrange.yaml
   kubectl delete pods --all --wait=false
   ```
   ```
   catalog: 62484480 bytes peak
   thumbs: 70737920 bytes peak
   search: 70946816 bytes peak
   ```

10. About a minute later, look for what the pods share:
    ```bash
    kubectl get pods
    kubectl describe pod <thumbs-pod> | grep -A12 'Last State'
    kubectl get pod <thumbs-pod> -o jsonpath='{.metadata.annotations}'; echo
    kubectl get limitrange
    kubectl describe limitrange defaults
    ```
    ```
    search-858765c6-rtlfw      0/1     CrashLoopBackOff   3 (12s ago)   57s
          Reason:       OOMKilled
          Exit Code:    137
        Limits:
          memory:  32Mi
    {"kubernetes.io/limit-ranger":"LimitRanger plugin set: memory request for container api; memory limit for container api"}
    ```
    The manifests never set a memory limit; the LimitRange did.

11. Give every app its own memory, based on the measured 62-71 MB peak:
    ```bash
    kubectl set resources deploy catalog thumbs search --requests=memory=96Mi --limits=memory=128Mi
    kubectl rollout status deploy/thumbs
    kubectl rollout status deploy/search
    kubectl rollout status deploy/catalog
    kubectl get pods
    ```
    All pods `1/1 Running`, 0 restarts.

### Scenario 2: "Developers complain that deploys are slow"

12. Make Priya's one-line change and run the pipeline the slow way (serial). In a second terminal, watch the rollout with timestamps:
    ```bash
    cd ../pipeline/catalog-api
    kubectl -n shop get pods -w | while read l; do echo "$(date +%T) $l"; done     # second terminal
    ```
    ```bash
    echo '# 1.5.1: friendlier 404 message for a missing course' >> app.py
    ./pipeline.sh 1.5.1 serial
    ```
    ```
    04:03:44  test    25.6 s  ok
    04:04:00  build   16.1 s  ok
    04:04:08  ship     8.3 s  ok
    04:05:33  deploy  85.0 s  ok
    total 135.0 s
    ```
    The rollout is 63% of the pipeline. In the watch, each new pod is `Running` in a second but `1/1` only after about 21 s, one at a time.

13. Find out why each stage is slow:
    ```bash
    grep -E '^#[0-9]+ (\[[0-9]/[0-9]\]|DONE|CACHED)' .ci/build.log | head -20
    docker image ls catalog-api
    tail -4 .ci/test.log
    cat .ci/deploy.log
    ```
    ```
    #7 [3/4] COPY . .
    #8 [4/4] RUN pip install --no-cache-dir -r requirements.txt
    #8 DONE 7.8s
    Ran 8 tests in 24.026s
    ```
    `COPY . .` comes before `pip install`, so every code change reruns pip; six tests each wait 4 s for a fake database (staged).

14. **Fix 1 (build)** and **fix 3 (rollout)**:
    ```bash
    diff -u Dockerfile ../fixes/Dockerfile
    cp ../fixes/Dockerfile Dockerfile
    kubectl diff -f ../fixes/shop.yaml | grep -E "^[-+] "
    kubectl apply -f ../fixes/shop.yaml
    kubectl -n shop rollout status deploy/catalog-api
    ```
    ```
    -      maxSurge: 1
    +      maxSurge: 2
    -          initialDelaySeconds: 20
    -          periodSeconds: 10
    +          periodSeconds: 2
    ```
    **Fix 2 (parallel jobs)** is already in `pipeline.sh`: `parallel` mode runs the tests in three shards while the image builds.

15. The first run after the fix is honest about the cache: the layer order changed, so pip runs once more.
    ```bash
    echo '# 1.5.2: course titles trimmed' >> app.py
    ./pipeline.sh 1.5.2 parallel
    ```
    Video: `total  21.7 s`.

16. Now the next one-line change (keep the watch running in the second terminal):
    ```bash
    echo '# 1.5.3: price shown in rupees on the course card' >> app.py
    ./pipeline.sh 1.5.3 parallel
    grep -E '^#[0-9]+ (\[[0-9]/[0-9]\]|DONE|CACHED)' .ci/build.log | head -20
    tail -4 .ci/test.log
    ```
    ```
    04:07:26  build    5.2 s  ok
    04:07:31  test    10.2 s  ok
    04:07:34  ship     3.4 s  ok
    04:07:41  deploy   6.7 s  ok
    total  20.4 s
    ```
    pip shows `CACHED`, and two new pods are ready in 3-4 seconds, then the next two. Your numbers will differ: ship took 3.2-8.3 s
    in the video depending on laptop load, and real dependencies can take minutes, not 7.8 s.

### Scenario 3: "You're on call. The site is down at 2 a.m."

17. Start the incident lab and the users (10 requests a second, logged to `runs/myrun.csv`). Wait about a minute so there is a baseline:
    ```bash
    cd ../..                  # back to interview/m21-l03-the-scenario-round
    ./lab/up.sh incident
    cd incident
    RUN=myrun docker compose --profile load up -d load
    ```
    Open Grafana at http://localhost:3000 (dashboard "catalog-slo"), the pager at http://localhost:8081 and the status page at http://localhost:8082.

18. The nightly pipeline deploys the staged release 1.5.0, then the page arrives (about 1.5 minutes later):
    ```bash
    ./deploy.sh 1.5.0 nightly-ci
    tail -2 incident/pager.log | jq -c "{ts, event, who, alert, summary}"
    ```
    ```
    {"ts":"04:19:58","event":"triggered","who":null,"alert":"CatalogErrorBudgetBurn","summary":"catalog-api: 19.73% of requests failing (SLO 99.5%)"}
    {"ts":"04:19:58","event":"notified","who":"asha","alert":null,"summary":null}
    ```

19. **Acknowledge, declare severity and roles, tell users** - before any fix:
    ```bash
    curl -s -X POST "127.0.0.1:8081/ack?page=1&who=asha" | jq -c .
    ./inc.sh asha "SEV2 declared: course list failing for most users. IC asha, ops lead rahul, comms priya"
    ./status.sh investigating "Course catalog" partial "We are investigating errors when loading the course list. Video playback and checkout are working normally. Next update in 15 minutes."
    ```

20. **Observe**: error ratio by route, the release running, and the last deploy:
    ```bash
    curl -sG 127.0.0.1:9090/api/v1/query --data-urlencode "query=sum by (route) (rate(http_requests_total{status=~\"5..\"}[1m])) / sum by (route) (rate(http_requests_total[1m]))" | jq -r ".data.result[] | \"\(.metric.route)  \(.value[1][0:6])\""
    curl -sG 127.0.0.1:9090/api/v1/query --data-urlencode "query=app_build_info" | jq -r ".data.result[].metric.version"
    tail -1 incident/deploys.log | jq -c "{start: (.start | strflocaltime(\"%H:%M:%S\")), version, by}"
    ```
    ```
    /api/courses  1
    1.5.0
    {"start":"04:18:31","version":"1.5.0","by":"nightly-ci"}
    ```
    The course list fails 100%, and a deploy lines up with the start: mitigate before the root cause.

21. Collect the evidence for Rahul's twist ("how do you know it was the deploy, not the database?"):
    ```bash
    docker compose logs api --since 1m --no-log-prefix | grep -m1 "\"level\": \"error\"" | jq -c "{ts, version, route, status, duration_ms, error}"
    docker compose exec -T db psql -U postgres -d catalog -c "SELECT round(extract(epoch FROM clock_timestamp() - query_start), 2) AS running_s, left(query, 64) AS query FROM pg_stat_activity WHERE state = 'active' AND query NOT LIKE '%pg_stat_activity%' ORDER BY 1 DESC LIMIT 3"
    ```
    ```
    {"ts":"2026-10-22T04:19:33.156","version":"1.5.0","route":"/api/courses","status":500,"duration_ms":1287.1,"error":"QueryCanceled: canceling statement due to statement timeout"}
          1.02 | SELECT course_id, count(*) FROM enrollments WHERE enrolled_at >
    ```

22. **Decide and roll back**, then **verify from the user's side** (wait about a minute after the rollback):
    ```bash
    ./inc.sh rahul "Errors began with the 1.5.0 deploy. /api/courses hits the 1 s statement timeout on the trending query. Propose rollback to 1.4.2."
    ./inc.sh asha "Approved: roll back to 1.4.2 now. Root cause after."
    ./deploy.sh 1.4.2 rahul
    docker compose logs load --since 25s --no-log-prefix | tail -2
    curl -s -o /dev/null -w "course list: HTTP %{http_code} in %{time_total} s\n" http://127.0.0.1:8080/api/courses
    ```
    ```
    04:22:02 last 10s: 100 requests, 0 failed (0%)
    course list: HTTP 200 in 0.007387 s
    ```

23. Update users, wait for the alert to resolve, and close:
    ```bash
    ./status.sh monitoring "Course catalog" operational "We rolled back a change that caused the errors. The course list is loading again. We are monitoring."
    ./inc.sh rahul "Error ratio back to 0 since the rollback. Course list loads."
    tail -1 incident/pager.log | jq -c "{ts, event, alert, ends_at}"
    ./status.sh resolved "Course catalog" operational "This incident has been resolved. The course list is loading normally for everyone. We will publish what happened and what we are changing."
    ./inc.sh asha "Resolved. Postmortem owner: rahul. Review on Friday."
    ```

24. **Postmortem timeline** from the real logs. Stop the users, move this run's logs next to its CSV, and build the timeline:
    ```bash
    docker compose --profile load stop load
    for f in pager status deploys timeline; do mv incident/$f.log runs/myrun-$f.log; done
    python3 timeline.py myrun
    ```
    No lab? `python3 timeline.py r2` prints the video's timeline:
    ```
    time to detect (first failure -> page):       1 min 24 s
    time to acknowledge (page -> ack):            0 min 22 s
    time to restore (first -> last failure):      2 min 21 s
    requests during impact: 1415, failed: 1051 (74.3%)
    error budget used: 1051 of 129,600 failures allowed in 30 days at 10 req/s (0.81%)
    ```

25. **Root cause, after the rollback:**
    ```bash
    docker compose exec -T db psql -U postgres -d catalog -c "EXPLAIN (ANALYZE, COSTS OFF) SELECT course_id, count(*) FROM enrollments WHERE enrolled_at > now() - interval '7 days' GROUP BY course_id" | grep -E "Scan|Execution"
    docker compose exec -T db psql -U postgres -d catalog -c "CREATE INDEX CONCURRENTLY enrollments_enrolled_at ON enrollments (enrolled_at)"
    docker compose exec -T db psql -U postgres -d catalog -c "EXPLAIN (ANALYZE, COSTS OFF) SELECT course_id, count(*) FROM enrollments WHERE enrolled_at > now() - interval '7 days' GROUP BY course_id" | grep -E "Scan|Execution"
    ```
    Before: `Parallel Seq Scan on enrollments`, about 363 ms. After: `Bitmap Index Scan on enrollments_enrolled_at`, about 133 ms.
    Blameless action items: the index, a cache for trending counts, and canary releases.

### Weak vs strong answers, and the rubric
| Question | Weak | Strong |
|---|---|---|
| Pods restarting | "I'd increase the memory and restart them." | "I'd read the last state and events first: exit 137, reason Error, failed liveness probe - the kubelet killed it." |
| Slow deploys | "I'd add caching and bigger runners." | "I'd time every stage first: the rollout was 85 of 135 s, so I'd start with probes and surge." |
| Down at 2 a.m. | "I'd find the bug and fix it." | "Acknowledge, severity, tell users; a deploy lines up, so roll back, verify as a user, then root cause." |

Follow-ups to prepare: *What if the rollback doesn't help?* (go back to observe; what else changed - data, traffic, a dependency).
*What would you automate?* (the checks you ran by hand). *What if you can't reach anyone?* (runbook, escalate by the rota, keep the timeline).
When you don't know: say so, give the method you'd use to find out. Never bluff.

Example rubric (not any company's real one), each scored 1-4: **structure**, **evidence**, **mitigation first**,
**communication**, **prevention and trade-offs**.

**Interview question:** *Deploys are slow. What's the first thing you do?* - Measure before changing anything: time every
stage from commit to running, fix the biggest one first, and show before and after numbers with what each fix costs.

## Common mistakes
- **Fixing the messenger:** turning off the liveness probe stops the restarts and hides the overload.
- **Optimizing without measuring:** the Docker build looked guilty; the rollout was 63% of the time.
- **Reading exit code 137 as "out of memory" every time:** check the reason and the events.
- **Debugging every app when everything broke at once:** look for what they share (node, namespace policy, dependency, config).
- **Going silent at 2 a.m.:** no acknowledgement, no status page, no timeline. Communication is part of the answer.
- Trade-offs to name: maxSurge 2 needs room for two extra pods; parallel test shards need isolated test data.

## Clean up
```bash
cd interview/m21-l03-the-scenario-round
./lab/down.sh
git checkout -- pipeline/catalog-api/app.py pipeline/catalog-api/Dockerfile   # undo the lesson's edits (if you cloned the repo)
rm -f incident/runs/myrun*
```

## Next
[M21-L04 · Full Mock Interview](../m21-l04-full-mock-interview/)
