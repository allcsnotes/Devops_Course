# M13-L03 · Pods
> Video: Module 13, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- What a pod is: the smallest deployable unit, one or more containers scheduled together that share one IP, localhost, IPC, the host name and volumes.
- How a node builds a pod: the `pause` container holds the shared namespaces; each container keeps its own filesystem and processes.
- Sharing files with an `emptyDir` volume, the sidecar pattern, and native sidecars (init containers with `restartPolicy: Always`).
- Init containers that run in order before the app, for example to wait for a database.
- Pod phases, container states and `restartPolicy`, read from real failures: ImagePullBackOff, CrashLoopBackOff, Completed, OOMKilled.
- How a pod stops (preStop, SIGTERM, grace period, SIGKILL), and why nobody replaces a bare pod.

## Before you start
- Docker Desktop (or Docker Engine on Linux), kind **v0.33.0**, kubectl **v1.37.1**.
- Node image `kindest/node:v1.37.0` (Kubernetes 1.37.0), pinned in `kind-cluster.yaml`.
- Optional: `jq` (one step) and `ts` from moreutils (adds timestamps to watch output).
- You know the cluster basics from [M13-L02](../m13-l02-your-first-cluster/).

## Files in this folder
| File | What it is |
|---|---|
| `kind-cluster.yaml` | Cluster `lab`: one control plane, two workers, pinned node image |
| `pods/web.yaml` | One nginx container with labels, a port, an env var and resource requests/limits |
| `pods/duo.yaml` | Two containers in one pod: nginx (`web`) and a curl container (`probe`) |
| `pods/shared.yaml` | A writer and a reader sharing one `emptyDir` volume |
| `pods/sidecar.yaml` | Pod `storefront`: nginx plus a native sidecar `log-shipper` that follows its access log |
| `pods/api.yaml` | Two init containers (`wait-for-db`, `fetch-config`) before a stand-in API |
| `pods/db.yaml` | A Postgres pod and a Service named `db` (the password is a fake lab value) |
| `pods/typo.yaml` | Staged failure: a typo in the image tag |
| `pods/crash.yaml` | Staged failure: a worker that exits with code 1 |
| `pods/done.yaml` | A pod that finishes successfully (`restartPolicy: OnFailure`) |
| `pods/oom.yaml` | A pod that is OOM-killed by its 32Mi memory limit (`restartPolicy: Never`) |
| `pods/graceful.yaml` | A Python app that handles SIGTERM, with a preStop hook |
| `pods/stubborn.yaml` | A Python app that ignores SIGTERM, grace period 10 s |
| `pods/tiny.yaml` | A distroless Python image with no shell, for `kubectl debug` |

## Follow along

1. Create the cluster and go into the `pods` folder.
   ```bash
   kind create cluster --config kind-cluster.yaml
   kubectl get nodes
   cd pods
   ls
   ```
   Wait until all three nodes (`lab-control-plane`, `lab-worker`, `lab-worker2`) are `Ready`.

2. Your first pod. Read `web.yaml` (apiVersion `v1`, kind `Pod`, labels, one container with a pinned image, `containerPort: 80`, `SITE_NAME`, requests and a memory limit), then:
   ```bash
   kubectl apply -f web.yaml
   kubectl get pods -o wide
   ```
   First `ContainerCreating` with no IP; a few seconds later:
   ```
   NAME   READY   STATUS    RESTARTS   AGE   IP           NODE          ...
   web    1/1     Running   0          14s   10.244.3.2   lab-worker2   ...
   ```
   Pod IPs, node names and ages will differ on your machine.

3. Read the whole story, then look inside.
   ```bash
   kubectl describe pod web
   kubectl logs web --tail 4
   kubectl exec -it web -- sh
   ```
   At the bottom of `describe`: `Scheduled` by default-scheduler, then the kubelet's `Pulling`, `Pulled`, `Created`, `Started`. When a pod misbehaves, read the events first. Inside the shell:
   ```bash
   echo $SITE_NAME
   hostname
   ps
   exit
   ```
   You should see `allcsvideos`, `web` (the pod's name), and `nginx: master process` as PID 1 with its worker processes.

4. Two containers, one pod.
   ```bash
   kubectl apply -f duo.yaml
   kubectl wait --for=condition=Ready pod/duo
   kubectl get pod duo -o wide
   kubectl exec duo -c probe -- curl -sI localhost:80
   ```
   You should see `duo 2/2 Running` with one IP, and `HTTP/1.1 200 OK` / `Server: nginx/1.29.8`: localhost in `probe` is localhost in `web`.

5. Prove what they share.
   ```bash
   kubectl exec duo -c web -- ip -4 addr show eth0
   kubectl exec duo -c probe -- ip -4 addr show eth0
   kubectl exec duo -c web -- hostname
   kubectl exec duo -c probe -- hostname
   kubectl exec duo -c web -- ls -l /proc/1/ns
   kubectl exec duo -c probe -- ls -l /proc/1/ns
   ```
   Same `inet` address and host name `duo` in both. In the namespace lists, `net`, `ipc` and `uts` have the same numbers in both containers; `mnt`, `pid` and `cgroup` differ:
   ```
   ipc -> ipc:[4026536448]        (same in both)
   mnt -> mnt:[4026536450]        (web)    mnt -> mnt:[4026536453]  (probe)
   net -> net:[4026536316]        (same in both)
   uts -> uts:[4026536447]        (same in both)
   ```

6. Meet the `pause` container on the node. Use the node from step 4 (`lab-worker2` in the video) and **your** pod sandbox ID and PID from each previous command:
   ```bash
   docker exec lab-worker2 crictl pods --name duo
   docker exec lab-worker2 crictl ps --pod <POD-ID>
   docker exec lab-worker2 crictl inspectp <POD-ID> | grep image-name
   docker exec lab-worker2 crictl inspectp -o go-template --template '{{.info.pid}}' <POD-ID>; echo
   docker exec lab-worker2 ps -o pid,args -p <PID>
   docker exec lab-worker2 readlink /proc/<PID>/ns/net
   ```
   You should see two containers (`probe`, `web`) but no pause among them; the sandbox image `registry.k8s.io/pause:3.10`; the PID's command `/pause`; and the same `net:[...]` number the containers showed. The shared network namespace belongs to pause.

7. Share files with an `emptyDir` volume.
   ```bash
   kubectl apply -f shared.yaml
   kubectl wait --for=condition=Ready pod/shared
   kubectl logs shared -c reader
   kubectl exec shared -c writer -- ls -l /data
   kubectl exec shared -c reader -- ls -l /input
   kubectl exec shared -c reader -- ls /data
   ```
   The reader prints the times the writer wrote; the same `out.log` appears at `/data` in one container and `/input` in the other; and `ls: /data: No such file or directory` in the reader: it sees only what it mounts.

8. A native sidecar: an init container with `restartPolicy: Always`.
   ```bash
   kubectl apply -f sidecar.yaml
   kubectl wait --for=condition=Ready pod/storefront
   kubectl get pod storefront
   kubectl exec storefront -c web -- wget -qO /dev/null localhost/courses
   kubectl exec storefront -c web -- wget -qO /dev/null localhost/
   kubectl logs storefront -c log-shipper
   ```
   You should see `storefront 2/2 Running`, a 404 for `/courses`, and:
   ```
   tail: can't open '/logs/access.log': No such file or directory
   tail: /logs/access.log has appeared; following end of new file
   ::1 - - [...] "GET /courses HTTP/1.1" 404 153 "-" "Wget" "-"
   ::1 - - [...] "GET / HTTP/1.1" 200 896 "-" "Wget" "-"
   ```
   Check the start order:
   ```bash
   kubectl describe pod storefront | grep -A12 '^Events'
   kubectl get pod storefront -o jsonpath='{.spec.initContainers[0].restartPolicy}'; echo
   ```
   `spec.initContainers{log-shipper}` is created and started before `spec.containers{web}` is even pulled; the restartPolicy is `Always`.

9. Init containers that wait for a dependency. In terminal 1, watch:
   ```bash
   kubectl get pods -l 'app in (api,db)' -w
   ```
   In terminal 2 (in the `pods` folder):
   ```bash
   kubectl apply -f api.yaml
   kubectl logs api -c wait-for-db
   ```
   `api` sits in `Init:0/2`, and the log says `waiting for db` / `nc: bad address 'db'`: there is no db yet, not even the name. Now start the database:
   ```bash
   kubectl apply -f db.yaml
   kubectl wait --for=condition=Ready pod/api --timeout=120s
   kubectl logs api -c wait-for-db --tail 3
   kubectl logs api -c fetch-config
   kubectl logs api
   ```
   The watch shows `db` going `Running`, then `api` `Init:1/2` -> `PodInitializing` -> `Running`. The logs end with `db is up`, `config written` and `api started with FEATURE_PLAYER=on`. Stop the watch with Ctrl+C.

10. Staged failure 1: a typo in the image tag (`alpnie`).
    ```bash
    kubectl apply -f typo.yaml
    sleep 20; kubectl get pod typo
    kubectl describe pod typo | grep -A10 '^Events'
    ```
    You should see `ImagePullBackOff`, and in the events `Failed to pull image "nginx:1.29.8-alpnie" ... NotFound`, `ErrImagePull`, `Back-off pulling image`.

11. Staged failure 2: a crash loop. Terminal 1:
    ```bash
    kubectl get pods --field-selector metadata.name=crash -w
    ```
    Terminal 2:
    ```bash
    kubectl apply -f crash.yaml
    kubectl logs crash
    ```
    The watch shows `Running`, `Error`, one quick restart, then `CrashLoopBackOff`, with longer and longer gaps (about 14 s, 28 s, 48 s, 82 s, 162 s in the video): the kubelet's back-off starts at 10 s and doubles, up to five minutes. Let it run a few minutes, then Ctrl+C. The log says `worker starting` / `cannot reach the queue`.

12. A success and an OOM kill.
    ```bash
    kubectl apply -f done.yaml -f oom.yaml
    sleep 10; kubectl get pods done oom
    kubectl get pod oom -o jsonpath='{.status.containerStatuses[0].state.terminated}' | jq .
    kubectl logs done
    ```
    You should see `done Completed`, `oom OOMKilled`, `"exitCode": 137, "reason": "OOMKilled"` (128 + 9 = SIGKILL), and `report built`.

13. Phase vs container state, side by side.
    ```bash
    kubectl get pods typo crash done oom -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,WAITING:.status.containerStatuses[0].state.waiting.reason,TERMINATED:.status.containerStatuses[0].state.terminated.reason,RESTARTS:.status.containerStatuses[0].restartCount
    ```
    You should see something like:
    ```
    NAME    PHASE       WAITING            TERMINATED   RESTARTS
    typo    Pending     ImagePullBackOff   <none>       0
    crash   Running     <none>             Error        6
    done    Succeeded   <none>             Completed    0
    oom     Failed      <none>             OOMKilled    0
    ```

14. How a pod stops. First the default grace period:
    ```bash
    kubectl get pod web -o jsonpath='{.spec.terminationGracePeriodSeconds}'; echo
    kubectl explain pod.spec.terminationGracePeriodSeconds | tail -9
    ```
    `30`, and `Defaults to 30 seconds.` Now a well-behaved app:
    ```bash
    kubectl apply -f graceful.yaml
    kubectl wait --for=condition=Ready pod/graceful --timeout=120s
    ```
    Terminal 1: `kubectl logs -f graceful`. Terminal 2:
    ```bash
    time kubectl delete pod graceful
    ```
    You should see:
    ```
    23:51:40 preStop: draining for 5 s
    23:51:45 SIGTERM received, finishing in-flight requests
    23:51:48 shutdown complete
    ...
    real	0m9.053s
    ```

15. An app that ignores SIGTERM (grace period 10 s).
    ```bash
    kubectl apply -f stubborn.yaml
    kubectl wait --for=condition=Ready pod/stubborn --timeout=120s
    ```
    Terminal 1: `kubectl logs -f stubborn`. Terminal 2:
    ```bash
    kubectl get pod stubborn -w -o custom-columns=NAME:.metadata.name,EXIT:.status.containerStatuses[0].state.terminated.exitCode,REASON:.status.containerStatuses[0].state.terminated.reason
    ```
    Terminal 3: `time kubectl delete pod stubborn`. The log shows `SIGTERM received, ignoring it`; exactly ten seconds later the watch shows exit code `137`: SIGKILL.

16. Nobody replaces a bare pod.
    ```bash
    kubectl get pod web -o wide
    kubectl delete pod web
    kubectl get pod web
    kubectl apply -f web.yaml
    kubectl wait --for=condition=Ready pod/web
    kubectl get pod web -o wide
    ```
    `Error from server (NotFound): pods "web" not found` - nothing brings it back. After apply it's a brand-new pod with a new IP (10.244.3.2 became 10.244.3.8 in the video).

17. `latest` tags change the pull policy.
    ```bash
    kubectl run tmp --image=nginx:latest --dry-run=server -o jsonpath='{.spec.containers[0].imagePullPolicy}'; echo
    kubectl run tmp --image=nginx:1.29.8-alpine --dry-run=server -o jsonpath='{.spec.containers[0].imagePullPolicy}'; echo
    ```
    `Always`, then `IfNotPresent`. (A server-side dry run creates nothing.)

18. Debug a distroless image that has no shell.
    ```bash
    kubectl apply -f tiny.yaml
    kubectl wait --for=condition=Ready pod/tiny --timeout=120s
    kubectl exec -it tiny -- sh
    kubectl debug -it tiny --image=busybox:1.37.0 --target=app -- sh
    ```
    `exec` fails (`executable file not found`). `kubectl debug` adds an ephemeral busybox container that shares the app's process namespace; inside it, run `ps` and you'll see `/usr/bin/python3.13 -m http.server 8080` as PID 1. Type `exit`.

## Common mistakes
- **Several apps in one pod.** They scale, deploy and die together. One app per pod, plus only helpers that share its life.
- **`latest` image tags.** They can change under you and differ between nodes, and they switch the pull policy to `Always`. Pin a version.
- **Bare pods in production.** Nobody recreates them after a delete or when their node dies. Use a Deployment (next lesson).
- **Ignoring `describe` events.** Image pull errors, back-offs and OOM kills are explained at the bottom of `kubectl describe`.
- **Debugging with `exec` in a distroless image.** There's no shell; use `kubectl debug` with an ephemeral container.
- **Not handling SIGTERM.** Handle it in your app and set the grace period longer than your real shutdown takes.

## Clean up
From the `pods` folder:
```bash
kubectl delete -f . --ignore-not-found
cd ..
kind delete cluster --name lab
```

## Next
[M13-L04 · Deployments and ReplicaSets](../m13-l04-deployments-and-replicasets/)
