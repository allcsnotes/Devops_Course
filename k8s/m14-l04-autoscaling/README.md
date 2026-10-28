# M14-L04 · Autoscaling
> Video: Module 14, Lesson 4. Watch it first, then follow along here.

## What you'll learn
- The three layers: the Horizontal Pod Autoscaler (more pods), the Vertical Pod Autoscaler (bigger pods), and node autoscalers (more machines).
- Where the numbers come from: kubelets -> metrics-server -> the Metrics API (`metrics.k8s.io`) -> the HPA controller every 15 s.
- The HPA formula: desired = ceil(current replicas x current metric / target), with CPU utilization measured against **requests**.
- `behavior`: fast scale-up, a stabilization window for scale-down (300 s by default), and why readiness decides when new pods help.
- VPA in recommendation-only mode, why VPA and HPA must not fight over the same metric, and what Pending pods mean for Cluster Autoscaler and Karpenter.

## Before you start
- Docker Desktop (or Docker Engine on Linux), kind **v0.33.0**, kubectl **v1.37.1**, `jq`.
- Node image `kindest/node:v1.37.0` (Kubernetes 1.37.0), pinned in `kind-cluster.yaml`.
- Requests, limits and probes from [M14-L03](../m14-l03-health-and-resources/).
- Load tests use real CPU on your laptop. Your percentages, timings and failure counts will differ from the video - the shape is what matters.
- Pinned add-ons used below: metrics-server **v0.9.0**, Vertical Pod Autoscaler **1.8.0** (recommender only).

## Files in this folder
| File | What it is |
|---|---|
| `kind-cluster.yaml` | Cluster `lab`: one control plane, two workers |
| `app/app.py`, `app/Dockerfile` | API with `GET /recommend?user=U&n=N` (hashes N times: real CPU), one worker at a time, 503 after 1.5 s in line; `STARTUP_SECONDS` cold start |
| `traffic/traffic.py`, `traffic/Dockerfile` | `python traffic.py <url> <seconds> <rate> <out>`: open-loop load; prints ok/timeout/err, p50/p95 and pods per second |
| `manifests/api.yaml`, `svc.yaml`, `traffic.yaml` | API: 3 replicas, CPU request = limit = 100m, 5 s warm-up, readiness probe; its Service; the traffic pod |
| `manifests/hpa.yaml` | HPA: CPU 50%, min 2, max 10, scale-down window 60 s (lab only; default 300) |
| `manifests/hpa-tuned.yaml` | A tuned HPA: CPU + memory, +4 pods per 15 s up, -20% per minute down after 300 s |
| `manifests/vpa.yaml` | VPA for `api` in `updateMode: "Off"` (recommend only) |
| `manifests/reserve.yaml` | Six pods requesting 4 CPUs each (more than two workers hold) |
| `manifests/api-noreq.yaml` | Staged mistake: the API with no requests |
| `manifests/pdb.yaml` | PodDisruptionBudget: `minAvailable: 2` for the API |

## Follow along

1. Cluster, images, the API, its Service and the traffic pod.
   ```bash
   kind create cluster --config kind-cluster.yaml
   docker build -q -t scale-api:1.0 app && docker build -q -t scale-traffic:1.0 traffic
   kind load docker-image scale-api:1.0 scale-traffic:1.0 --name lab
   kubectl create namespace allcsvideos
   kubectl config set-context --current --namespace allcsvideos
   kubectl apply -f manifests/api.yaml -f manifests/svc.yaml -f manifests/traffic.yaml
   kubectl rollout status deploy/api && kubectl rollout status deploy/traffic
   kubectl get pods -o wide
   ```

2. Metrics: none yet, then metrics-server, then the kind fix.
   ```bash
   kubectl top pods
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml
   sleep 45
   kubectl -n kube-system get pods -l k8s-app=metrics-server
   kubectl -n kube-system logs deploy/metrics-server --tail=3
   ```
   `error: Metrics API not available`, then a `0/1` metrics-server whose log says `tls: failed to verify certificate: x509: cannot validate certificate ... because it doesn't contain any IP SANs`. kind's kubelets use self-signed certificates, so for this lab only:
   ```bash
   kubectl -n kube-system patch deployment metrics-server --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
   kubectl -n kube-system rollout status deploy/metrics-server
   kubectl get apiservice v1beta1.metrics.k8s.io
   kubectl top nodes
   kubectl top pods
   kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespaces/allcsvideos/pods | jq -c '.items[0] | {name: .metadata.name, window, usage: .containers[0].usage}'
   ```
   `AVAILABLE True`, idle pods at about 4m CPU, and the raw JSON the HPA sees: `{"window":"31.544s","usage":{"cpu":"3353316n","memory":"11392Ki"}}`. Never use `--kubelet-insecure-tls` in production.

3. Install the VPA recommender (CRDs, RBAC and recommender only - no updater, no admission controller) and a recommend-only VPA, so it can watch the load tests.
   ```bash
   VPA=https://raw.githubusercontent.com/kubernetes/autoscaler/vertical-pod-autoscaler-1.8.0/vertical-pod-autoscaler/deploy
   kubectl apply -f $VPA/vpa-v1-crd-gen.yaml -f $VPA/vpa-rbac.yaml -f $VPA/recommender-deployment.yaml
   kubectl -n kube-system rollout status deploy/vpa-recommender
   kubectl apply -f manifests/vpa.yaml
   kubectl get vpa
   ```

4. **The hook: launch day with three fixed pods.** Terminal 2:
   ```bash
   kubectl exec deploy/traffic -- python traffic.py 'http://api/recommend?user=lukas&n=40000' 90 20 /tmp/hook
   ```
   Terminal 1, about 30 s in: `kubectl top pods`. Every API pod sits at about `100m` (its limit), p95 climbs past 1.5 s, and the run ends with roughly one request in six failing (`done: 1800 requests, 279 failed` in the video).

5. Create the HPA.
   ```bash
   kubectl autoscale deployment api --cpu=50% --min=2 --max=10 --dry-run=client -o yaml
   kubectl explain hpa.spec.behavior.scaleDown.stabilizationWindowSeconds | sed -n '/DESCRIPTION/,$p'
   kubectl apply -f manifests/hpa.yaml
   kubectl get hpa api -w
   ```
   The dry run prints an `autoscaling/v2` HPA with one `cpu` / `Utilization` / `50` metric; `explain` confirms the defaults: `scale up: 0`, `scale down: 300`. If you run this right after step 4, the HPA still sees the busy window (`cpu: 94%/50%` in the video) and acts on it: 3 x 94 / 50 = 5.64 -> 6 replicas. Then the readings fall, and after the 60 s window it drops to the minimum, 2. Stop the watch with Ctrl+C.

6. **Launch day with the HPA (5 minutes).** Three terminals:
   - terminal 3: `kubectl get hpa api -w`
   - terminal 4 (optional): `kubectl get pods -l app=api -w`
   - terminal 2: `kubectl exec deploy/traffic -- python traffic.py 'http://api/recommend?user=lukas&n=40000' 300 20 /tmp/launch`

   Midway, in terminal 1: `kubectl top pods`. You should see replicas climb in steps, each one the formula:
   ```
   09:16:01 api    Deployment/api   cpu: 90%/50%    2   10   2      (2 x 90/50 = 3.6 -> 4)
   09:16:16 api    Deployment/api   cpu: 100%/50%   2   10   4
   09:17:01 api    Deployment/api   cpu: 92%/50%    2   10   8      (4 x 94/50 = 7.52 -> 8)
   09:17:47 api    Deployment/api   cpu: 57%/50%    2   10   10     (8 x 62/50 = 9.92 -> 10, the max)
   ```
   Errors stop once enough pods are ready. In the pod watch, new pods are `0/1` for about 14 s (the warm-up) before they get traffic, and swamped old pods can briefly flip to `0/1` too. After the run, CPU drops, but replicas stay at 10 for the 60 s window, then step down to 2. Then:
   ```bash
   kubectl describe hpa api | sed -n '/Metrics:/,$p'
   ```
   The events list `New size: 6, 4, 8, 10 ... cpu resource utilization (percentage of request) above target`, then `5, 4, 3, 2 ... All metrics below target`, and the behavior used: scale up by `Pods 4` or `Percent 100` every 15 s.

7. Tuning and other metrics.
   ```bash
   cat manifests/hpa-tuned.yaml
   kubectl apply -f manifests/hpa-tuned.yaml --dry-run=server
   kubectl get apiservices | grep -E 'NAME|metrics'
   ```
   The server accepts it (`configured (server dry run)`). Only `v1beta1.metrics.k8s.io` exists: custom metrics (`custom.metrics.k8s.io`) and external metrics need an adapter such as Prometheus Adapter (module 16) or KEDA.

8. What did the VPA learn?
   ```bash
   kubectl get vpa
   kubectl describe vpa api | sed -n '/Recommendation:/,/Events:/p'
   ```
   In the video: `CPU 224m`, `MEM 250Mi`, `PROVIDED True` - more than double the 100m we gave. 250Mi is the recommender's minimum, not real usage, and with only minutes of history the bounds are wide (68m to over 15 cores). Don't switch it to `Recreate` while an HPA scales on the same CPU metric: the two loops would chase each other.

9. Pods that don't fit: the node autoscaler's cue.
   ```bash
   kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.allocatable.cpu
   kubectl apply -f manifests/reserve.yaml
   sleep 5; kubectl get pods -l app=reserve -o wide
   kubectl describe pod <A-PENDING-RESERVE-POD> | sed -n '/Events:/,$p'
   kubectl describe node lab-worker | grep -A6 'Allocated resources'
   kubectl delete -f manifests/reserve.yaml
   ```
   Some pods run, the rest stay `Pending`: `0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 Insufficient cpu.` How many fit depends on your Docker VM's CPU count (10 in the video: four ran, two pending). kind can't buy machines, so we stop here; Cluster Autoscaler or Karpenter would add a node now.

10. Staged mistake: an HPA without requests.
    ```bash
    kubectl apply -f manifests/api-noreq.yaml
    kubectl autoscale deployment api-noreq --cpu=50% --min=2 --max=10
    sleep 40; kubectl get hpa api-noreq
    kubectl describe hpa api-noreq | grep -E 'Warning|ScalingActive'
    ```
    `cpu: <unknown>/50%`, and `failed to get cpu utilization: missing request for cpu in container api`. It never errors loudly; it just never scales.

11. PodDisruptionBudgets during a drain. Pick the worker that runs an API pod:
    ```bash
    kubectl get pods -l app=api -o wide
    kubectl apply -f manifests/pdb.yaml
    kubectl get pdb api
    kubectl drain <NODE> --ignore-daemonsets --delete-emptydir-data --timeout=30s
    kubectl uncordon <NODE>
    ```
    With 2 API pods and `minAvailable: 2`, `ALLOWED DISRUPTIONS 0`. Other pods are evicted, but the API pod: `Cannot evict pod as it would violate the pod's disruption budget.` The drain times out. Always uncordon afterwards.

## Common mistakes
- **An HPA without requests.** CPU utilization is a percentage of the request: no request, no scaling.
- **min equal to max.** Nothing left to decide. Keep min at what survives a node failure, max at what your nodes and budget allow.
- **Flapping.** Pods added and removed every minute, each paying a cold start. Use the stabilization window and scale-down policies; don't copy the lab's 60 s window to production.
- **Scaling an I/O-bound app on CPU.** A service waiting on a database can be overloaded at 10% CPU. Scale on requests in flight, latency or queue length (custom metrics, KEDA).
- **Forgetting PodDisruptionBudgets.** Node scale-downs evict pods; without a budget they can take every replica at once.
- **Cold starts.** New pods need seconds, new nodes minutes. Keep min replicas high enough for the first spike, make startup fast, scale before 100%.
- **VPA and HPA on the same metric.** They fight. Use different signals, or VPA in `Off` mode to choose requests.

## Clean up
```bash
kind delete cluster --name lab
docker rmi scale-api:1.0 scale-traffic:1.0
```

## Next
[M14-L05 · Jobs, CronJobs and DaemonSets](../m14-l05-jobs-cronjobs-and-daemonsets/)
