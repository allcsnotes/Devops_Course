# M14-L03 · Health and Resources
> Video: Module 14, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- The three probes: readiness (may it get traffic?), liveness (is it stuck?), startup (has it started?), and how fast each acts (about `periodSeconds x failureThreshold`).
- Probe mechanisms (`httpGet`, `tcpSocket`, `exec`, `grpc`), their defaults, and the deadly mistake: a liveness probe that checks a dependency.
- Requests (reservations the scheduler keeps) vs limits (cgroup ceilings): CPU is throttled, memory is OOMKilled with exit code 137.
- QoS classes (Guaranteed, Burstable, BestEffort), `oom_score_adj`, and eviction order.
- Namespace budgets with ResourceQuota and defaults with LimitRange; sizing requests from `kubectl top`.

## Before you start
- Docker Desktop (or Docker Engine on Linux), kind **v0.33.0**, kubectl **v1.37.1**, `jq`.
- Node image `kindest/node:v1.37.0` (Kubernetes 1.37.0), pinned in `kind-cluster.yaml`.
- Deployments and the traffic generator idea from [M13-L04](../m13-l04-deployments-and-replicasets/), EndpointSlices from [M13-L05](../m13-l05-services-and-dns/).
- Several steps need two or three terminals (a watch, the traffic generator, commands). Open them all in this folder.
- Your pod names, IPs and timings will differ from the video. Copy your own names from `kubectl get pods`.

## Files in this folder
| File | What it is |
|---|---|
| `kind-cluster.yaml` | Cluster `lab`: one control plane, two workers |
| `app/app.py`, `app/Dockerfile` | API with switches: `/healthz`, `/readyz`, `/healthz/deep`, `/work?ms=N`, and `POST /admin/{deadlock,drain,undrain,leak,burn}`; `STARTUP_SECONDS` warm-up |
| `traffic/traffic.py`, `traffic/Dockerfile` | 20 requests/s; prints `ok`, `timeout`, `err` and pods per second |
| `manifests/api-noprobe.yaml` | The hook: 3 replicas, no probes |
| `manifests/api.yaml` | Readiness (`/readyz`, 2 s x 2) and liveness (`/healthz`, 5 s x 3) |
| `manifests/svc.yaml`, `traffic.yaml` | Service `api` and the traffic pod |
| `manifests/warm-bad.yaml`, `warm-fixed.yaml` | 40 s warm-up with an impatient liveness probe; the startupProbe fix |
| `manifests/probe-kinds.yaml` | tcpSocket, exec and httpGet probes with default timings |
| `manifests/db.yaml`, `api-deep.yaml` | A Postgres stand-in (fake password) and a liveness probe that checks it (staged mistake) |
| `manifests/huge.yaml`, `burn.yaml`, `work.yaml`, `leaky.yaml`, `qos.yaml` | Requests too big, CPU limit, throttling latency, memory leak, the three QoS classes |
| `manifests/team/quota.yaml`, `team/limits.yaml` | ResourceQuota and LimitRange for namespace `team-a` |
| `manifests/api-final.yaml` | Probes plus requests (50m / 64Mi) and a memory limit (128Mi) |

## Follow along

1. Cluster, images, the API without probes, a Service and the traffic pod.
   ```bash
   kind create cluster --config kind-cluster.yaml
   docker build -q -t health-api:1.0.0 app
   docker build -q -t health-traffic:1.0 traffic
   kind load docker-image health-api:1.0.0 health-traffic:1.0 --name lab
   kubectl create namespace allcsvideos
   kubectl config set-context --current --namespace allcsvideos
   kubectl apply -f manifests/api-noprobe.yaml -f manifests/svc.yaml -f manifests/traffic.yaml
   kubectl rollout status deploy/api && kubectl rollout status deploy/traffic
   kubectl get pods -o wide
   ```

2. **The hook: a deadlock with no probes.** Terminal 2 (traffic, 60 s):
   ```bash
   kubectl exec deploy/traffic -- python traffic.py http://api 60 /tmp/hook
   ```
   Terminal 1, a few seconds later (use one of your API pod names, and another pod's name for the curl; the IP is the deadlocked pod's, from `-o wide`):
   ```bash
   kubectl exec <API-POD> -- curl -s -X POST localhost:8080/admin/deadlock
   sleep 20; kubectl get pods -l app=api
   kubectl exec <OTHER-API-POD> -- curl -sS -m 5 <DEADLOCKED-POD-IP>:8080/
   kubectl logs <API-POD>
   ```
   All pods `1/1 Running`, `0` restarts - yet `curl: (28) Operation timed out after 5011 milliseconds with 0 bytes received`. The traffic shows `timeout=` every second and ends with `done: 1200 requests, 241 failed`. Kubernetes only restarts a container that exits.

3. Add both probes.
   ```bash
   kubectl apply -f manifests/api.yaml
   kubectl rollout status deploy/api
   kubectl get pods -l app=api -o wide
   ```

4. Readiness under traffic. Terminal 3 (watch):
   ```bash
   kubectl get endpointslices -l kubernetes.io/service-name=api -w -o custom-columns='ENDPOINTS:.endpoints[*].addresses[0],READY:.endpoints[*].conditions.ready'
   ```
   Terminal 2: `kubectl exec deploy/traffic -- python traffic.py http://api 50 /tmp/ready`. Terminal 1:
   ```bash
   kubectl exec <API-POD> -- curl -s -X POST localhost:8080/admin/drain
   sleep 8; kubectl get pods -l app=api
   kubectl describe pod <API-POD> | grep -A2 Readiness
   sleep 10; kubectl exec <API-POD> -- curl -s -X POST localhost:8080/admin/undrain
   sleep 5; kubectl get pods -l app=api
   ```
   The slice flips that endpoint to `false`, the pod is `0/1 Running` with 0 restarts (alive, just out of rotation), `Readiness probe failed: HTTP probe failed with statuscode: 503`, then back to `true`. Traffic: `done: 1000 requests, 0 failed`.

5. The deadlock again, with both probes. Terminal 3: `kubectl get pods -l app=api -w`. Terminal 2: `kubectl exec deploy/traffic -- python traffic.py http://api 60 /tmp/live`. Terminal 1:
   ```bash
   kubectl exec <API-POD> -- curl -s -X POST localhost:8080/admin/deadlock
   sleep 30; kubectl get pods -l app=api
   kubectl events --for pod/<API-POD>
   kubectl logs <API-POD> --previous
   ```
   You should see readiness give up about 5 s after the deadlock (`0/1`), liveness restart it about 15 s after (`RESTARTS 1`), and `Ready` again 5 s later:
   ```
   08:42:18 api-7686648c5-g287j   0/1     Running   0          2m9s
   08:42:29 api-7686648c5-g287j   0/1     Running   1 (1s ago)   2m20s
   08:42:34 api-7686648c5-g287j   1/1     Running   1 (6s ago)   2m25s
   ```
   Events: `Liveness probe failed ... context deadline exceeded`, then `Killing ... failed liveness probe, will be restarted`. Traffic: `23 failed` (vs 241), all in the first seconds. Readiness protected the users; liveness fixed the pod.

6. A slow starter killed by liveness. Terminal 3: `kubectl get pods -l app=warm -w`. Terminal 1:
   ```bash
   kubectl apply -f manifests/warm-bad.yaml
   ```
   Wait about two minutes. Restarts at 16, 32, 46 s, then `CrashLoopBackOff` - and `1/1` READY the whole time (no readiness probe). Then:
   ```bash
   kubectl get pods -l app=warm
   kubectl logs <WARM-POD> --previous
   kubectl events --for pod/<WARM-POD> | grep -E 'Liveness|Killing|BackOff'
   ```
   The previous log ends at `warming up: loading the catalog, 10 of 40 s`, then `SIGTERM`.

7. The fix: a startup probe (up to 12 x 5 = 60 s).
   ```bash
   kubectl apply -f manifests/warm-fixed.yaml
   ```
   Wait about a minute (watch still running), then:
   ```bash
   kubectl get pods -l app=warm
   kubectl logs <NEW-WARM-POD>
   kubectl events --for pod/<NEW-WARM-POD> | grep -E 'Startup|Killing|Started'
   ```
   `0/1` while warming up, `Startup probe failed ... connection refused` about 8 times, no kills; `1/1`, `0` restarts after about 46 s, and the log ends with `listening on :8080`.

8. Probe mechanisms and defaults.
   ```bash
   kubectl apply -f manifests/probe-kinds.yaml
   kubectl wait --for=condition=Ready pod/probe-kinds --timeout=60s
   kubectl describe pod probe-kinds | grep -E 'Liveness|Readiness|Startup'
   kubectl explain pod.spec.containers.livenessProbe | grep -A3 -E '^  (failureThreshold|initialDelaySeconds|periodSeconds|successThreshold|timeoutSeconds)'
   kubectl explain pod.spec.containers.livenessProbe.grpc | grep -A1 -E '^  (port|service)'
   ```
   You should see:
   ```
   Liveness:       http-get http://:8080/healthz delay=0s timeout=1s period=10s successThreshold=1 failureThreshold=3
   Readiness:      exec [curl -sf localhost:8080/readyz] delay=0s timeout=1s period=10s successThreshold=1 failureThreshold=3
   Startup:        tcp-socket :8080 delay=0s timeout=1s period=10s successThreshold=1 failureThreshold=3
   ```

9. **Staged mistake: liveness that checks the database.**
   ```bash
   kubectl apply -f manifests/db.yaml -f manifests/api-deep.yaml
   kubectl rollout status deploy/db --timeout=180s && kubectl rollout status deploy/api-deep
   kubectl get pods -l 'app in (db,api-deep)'
   ```
   (While Postgres is still being pulled, the api-deep pods already restart - the first warning.) Terminal 3: `kubectl get pods -l app=api-deep -w`. Terminal 1:
   ```bash
   kubectl scale deploy/db --replicas=0
   kubectl get pods -l 'app in (db,api-deep)'
   ```
   Wait 45 s: all three API pods restart in the same second, every 15 s. Then:
   ```bash
   kubectl events --for pod/<API-DEEP-POD> | grep -E 'Liveness|Killing'
   kubectl delete -f manifests/api-deep.yaml -f manifests/db.yaml
   ```
   `HTTP probe failed with statuscode: 503`, `Killing`. Restarting the API can't fix the database.

10. Install metrics-server v0.9.0 (with `--kubelet-insecure-tls`, needed on kind only because its kubelets use self-signed certificates - lab only).
    ```bash
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml
    kubectl -n kube-system patch deploy metrics-server --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
    kubectl -n kube-system rollout status deploy/metrics-server --timeout=180s
    sleep 30; kubectl top nodes
    ```

11. What the scheduler sees.
    ```bash
    kubectl describe node lab-worker | grep -A10 -E '^(Capacity|Allocatable):' | grep -v hugepages
    kubectl describe node lab-worker | grep -A5 'Allocated resources'
    kubectl get --raw /api/v1/nodes/lab-worker/proxy/configz | jq -c '.kubeletconfig | {evictionHard, kubeReserved, systemReserved}'
    kubectl apply -f manifests/huge.yaml
    sleep 5; kubectl get pod huge
    kubectl events --for pod/huge
    kubectl delete pod huge
    ```
    Capacity equals Allocatable on kind (no reservations, eviction thresholds `0%`); all nodes share your Docker VM's CPUs. `huge` (12 CPUs) stays `Pending`: `0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 Insufficient cpu.` If your Docker VM has more than 12 CPUs, raise the request in `huge.yaml`.

12. CPU limit = throttling.
    ```bash
    kubectl apply -f manifests/burn.yaml
    kubectl wait --for=condition=Ready pod/burn && sleep 5
    kubectl exec burn -- curl -s -X POST 'localhost:8080/admin/burn?seconds=150'
    sleep 45; kubectl top pod burn
    kubectl exec burn -- cat /sys/fs/cgroup/cpu.max
    kubectl exec burn -- cat /sys/fs/cgroup/cpu.stat
    sleep 10; kubectl exec burn -- cat /sys/fs/cgroup/cpu.stat
    ```
    `burn 200m` (exactly the limit), `cpu.max` = `20000 100000`, and `nr_throttled` grows almost as fast as `nr_periods` (114 of 115 periods in the video).

13. What throttling does to latency.
    ```bash
    kubectl apply -f manifests/work.yaml
    kubectl wait --for=condition=Ready pod/work-limited pod/work-unlimited
    kubectl get pods work-limited work-unlimited -o custom-columns='NAME:.metadata.name,IP:.status.podIP,CPU_LIMIT:.spec.containers[0].resources.limits.cpu'
    kubectl exec deploy/api -- sh -c 'for i in 1 2 3 4 5; do curl -s -o /dev/null -w "%{time_total}s " <UNLIMITED-IP>:8080/work?ms=100; done; echo'
    kubectl exec deploy/api -- sh -c 'for i in 1 2 3 4 5; do curl -s -o /dev/null -w "%{time_total}s " <LIMITED-IP>:8080/work?ms=100; done; echo'
    ```
    About 0.1-0.5 s unlimited vs about 1.1-1.4 s limited: ten times slower, on a node with idle cores.

14. Memory limit = OOMKilled. Terminal 3: `kubectl get pod --field-selector metadata.name=leaky -w`. Terminal 1:
    ```bash
    kubectl apply -f manifests/leaky.yaml
    kubectl wait --for=condition=Ready pod/leaky && sleep 5
    kubectl exec leaky -- curl -s -X POST localhost:8080/admin/leak
    sleep 20; kubectl get pod leaky
    kubectl get pod leaky -o jsonpath='{.status.containerStatuses[0].lastState}' | jq
    kubectl logs leaky --previous | tail -4
    kubectl exec leaky -- cat /sys/fs/cgroup/memory.max
    ```
    `OOMKilled` about 15 s in, restarted at once; `"exitCode": 137, "reason": "OOMKilled"`; the previous log ends at `leak: holding 52 MiB`; `memory.max` = `67108864` (64 MiB).

15. QoS classes.
    ```bash
    kubectl apply -f manifests/qos.yaml
    kubectl wait --for=condition=Ready pod/qos-guaranteed pod/qos-burstable pod/qos-besteffort
    kubectl get pods qos-guaranteed qos-burstable qos-besteffort -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass
    for p in qos-guaranteed qos-burstable qos-besteffort; do echo "$p $(kubectl exec $p -- cat /proc/1/oom_score_adj)"; done
    ```
    `Guaranteed -997`, `Burstable 992` (depends on your node's memory: 1000 - 1000 x request / node memory), `BestEffort 1000` (first to die).

16. Namespace budgets.
    ```bash
    kubectl create namespace team-a
    kubectl apply -f manifests/team/quota.yaml
    kubectl run p1 -n team-a --image=health-api:1.0.0
    kubectl apply -f manifests/team/limits.yaml
    for p in p1 p2 p3; do kubectl run $p -n team-a --image=health-api:1.0.0; done
    kubectl get pod p1 -n team-a -o jsonpath='{.spec.containers[0].resources}'; echo
    kubectl run p4 -n team-a --image=health-api:1.0.0
    kubectl describe quota team-quota -n team-a
    ```
    First `failed quota: team-quota: must specify limits.memory ... requests.cpu ... requests.memory`. With the LimitRange, p1-p3 get `{"limits":{"memory":"128Mi"},"requests":{"cpu":"100m","memory":"64Mi"}}`, and p4 is `Forbidden: exceeded quota ... used: requests.cpu=300m, limited: requests.cpu=300m`.

17. Measure, then size. Terminal 2: `kubectl exec deploy/traffic -- python traffic.py http://api 70 /tmp/top`. Terminal 1, after about 30 s:
    ```bash
    kubectl top pods -l app=api
    kubectl get pods -l app=api -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass
    kubectl apply -f manifests/api-final.yaml
    kubectl rollout status deploy/api
    kubectl get pods -l app=api -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass,READY:.status.containerStatuses[0].ready
    ```
    About 30m CPU and 12-17Mi per pod under 20 requests/s; the pods are `BestEffort` before and `Burstable`, ready, after.

## Common mistakes
- **No probes.** A deadlocked pod stays in rotation forever. Every long-running container needs readiness, and most need liveness.
- **Liveness the same as readiness.** An overloaded pod gets restarted when it's busiest. Give liveness a cheap check, more patience and a higher threshold.
- **Probes that call dependencies.** Liveness checks the process, nothing else.
- **Tight CPU limits.** Throttling turns into latency (10x in step 13). Always set CPU requests; if you set CPU limits, set them well above normal use and watch throttling.
- **Memory limits below real usage.** OOMKilled on every peak, then CrashLoopBackOff. Size from measured peaks, with headroom.
- **No requests at all.** BestEffort pods are scheduled blind and evicted first. A LimitRange with defaults is the safety net for every namespace.

## Clean up
```bash
kind delete cluster --name lab
docker rmi health-api:1.0.0 health-traffic:1.0
```

## Next
[M14-L04 · Autoscaling](../m14-l04-autoscaling/)
