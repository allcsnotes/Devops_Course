# M14-L06 · Troubleshooting Kubernetes
> Video: Module 14, Lesson 6. Watch it first, then follow along here.

## What you'll learn
- A six-step method: symptom (`get pods -o wide`), `describe` from the bottom, `logs --previous`, look inside, walk the path, check the cluster.
- What each STATUS word means: which stage the pod is stuck in, and where to look next.
- Real, staged failures: a renamed config key (CrashLoopBackOff), a bad tag and missing registry credentials (ImagePullBackOff), a missing Secret (CreateContainerConfigError), OOMKilled, three kinds of Pending.
- Path problems where every pod looks healthy: a wrong probe port, a selector mismatch, a short DNS name from another namespace, a NetworkPolicy.
- Debugging distroless images with `kubectl debug`, debugging a node, and `port-forward`.

## Before you start
- Docker Desktop (or Docker Engine on Linux), kind **v0.33.0**, kubectl **v1.37.1**.
- Node image `kindest/node:v1.37.0` (Kubernetes 1.37.0), pinned in `kind-cluster.yaml`.
- Everything from modules 13 and 14 so far, especially probes ([M14-L03](../m14-l03-health-and-resources/)) and Services ([M13-L05](../m13-l05-services-and-dns/)).
- Every failure here is staged on purpose. Pod names, IPs and ages will differ: copy your own from `kubectl get pods`.
- Registry and SMTP passwords below are fake lab values.

## Files in this folder
| File | What it is |
|---|---|
| `kind-cluster.yaml` | Cluster `lab`: one control plane, one worker, longer leader-election timings |
| `lab/up.sh`, `lab/down.sh` | Build the whole lab (cluster, images, healthy app, private registry, `ops` namespace) and remove it |
| `app/app.py`, `app/Dockerfile` | Catalog API on a distroless Python image (no shell); refuses to start without `DATABASE_URL` |
| `manifests/base/` | The last good state: ConfigMap with `DATABASE_URL`, API 2.4.0, nginx storefront (`/api/` -> the API), a netshoot `probe` pod |
| `manifests/release-2.5.0/` | The broken release: image 2.5.0 and a ConfigMap whose key was renamed to `DB_URL` |
| `manifests/registry/registry.yaml` | Private registry `registry:3.1.2` on the worker at `localhost:5001`, basic auth |
| `manifests/staged/admin.yaml` | An image from that private registry, no pull secret |
| `manifests/staged/mailer.yaml` | Needs Secret `mailer-smtp`, which doesn't exist |
| `manifests/staged/thumbnailer.yaml` | Leaks 2 MiB/s against a 64Mi limit |
| `manifests/staged/report.yaml`, `transcoder.yaml`, `uploads.yaml` | Pending: 20 CPUs; `disktype: ssd` selector; a claim for StorageClass `fast-ssd` |
| `manifests/staged/catalog.yaml`, `search.yaml` | Readiness probe on the wrong port; Service selector `app=search-api` vs pods `app=search` |
| `manifests/staged/deny-api.yaml`, `allow-storefront.yaml` | A NetworkPolicy that forgot the storefront, and the fix |

## Follow along

1. Build the lab (3-5 minutes).
   ```bash
   bash lab/up.sh
   cd manifests
   kubectl get pods
   kubectl exec probe -- curl -s storefront/api/courses; echo
   ```
   Two API pods, two storefront pods and `probe`, all Running; the storefront answers `{"version": "2.4.0", ...}`.

2. **The hook.** Terminal 2 (keep it running - it's your incident timeline): `kubectl get pods -l app=api -w`. Terminal 1, the release:
   ```bash
   date +%T; kubectl apply -f release-2.5.0/
   sleep 40
   kubectl get pods -l app=api
   kubectl exec probe -- curl -s storefront/api/courses; echo
   ```
   The new pod says `Error` with restarts, but the two old pods still answer (version 2.4.0). Now do what Rahul did at 11 p.m. - delete the old 2.4.0 pods:
   ```bash
   kubectl get pods -l app=api -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image
   date +%T; kubectl delete pod <OLD-POD-1> <OLD-POD-2>
   sleep 35
   kubectl get pods -l app=api
   kubectl exec probe -- curl -s -i storefront/api/courses | head -1
   ```
   Three API pods in `Error`, and `HTTP/1.1 502 Bad Gateway`. Deleting made it worse.

3. Step 1, the symptom.
   ```bash
   kubectl get pods -o wide
   ```
   Every API pod `0/1` with restarts (`CrashLoopBackOff`, `Running` or `Error` - the same loop caught at different moments), all on `lab-worker`; the storefront is fine.

4. Step 2, describe - read Last State and the events from the bottom up. Use one of the recreated 2.4.0 pods:
   ```bash
   kubectl describe pod <API-POD>
   kubectl events --for pod/<API-POD>
   ```
   Image `catalog-api:2.4.0` (the old version - so the image isn't the problem), `Last State: Terminated, Reason: Error, Exit Code: 1` (the app gave up by itself; 137 would mean killed), and events `BackOff`, `Readiness probe failed ... connection refused` - no pull error, no scheduling problem.

5. Step 3, logs.
   ```bash
   kubectl logs <API-POD> --previous
   ```
   `FATAL: DATABASE_URL is not set. Refusing to start.` (Plain `kubectl logs` also works while the current container is dead; once a new container runs, you need `--previous`.)

6. Compare with what worked.
   ```bash
   kubectl rollout history deployment/api
   kubectl diff -f base/api-config.yaml
   ```
   Revision 2 is the release (no change cause). The diff:
   ```
   -  DB_URL: postgres://api@db.allcsvideos.internal:5432/catalog
   +  DATABASE_URL: postgres://api@db.allcsvideos.internal:5432/catalog
   ```
   The release renamed the key. That also explains the hook: `envFrom` is read at container start, so the recreated pods read the renamed key too.

7. The fix: one change, then one restart (env vars are only read at start).
   ```bash
   date +%T; kubectl apply -f base/api-config.yaml
   kubectl rollout restart deployment/api
   kubectl rollout status deployment/api
   kubectl get pods -l app=api
   kubectl exec probe -- curl -s storefront/api/courses; echo
   ```
   Two pods `1/1`, 0 restarts, and the storefront answers from version `2.5.0`. Look at the watch in terminal 2: that's your incident timeline (then Ctrl+C).

8. ImagePullBackOff, cause 1: a tag that doesn't exist.
   ```bash
   kubectl set image deployment/storefront web=nginx:1.29.88
   sleep 45
   kubectl get pods -l app=storefront
   kubectl exec probe -- curl -s -o /dev/null -w '%{http_code}\n' storefront/
   kubectl events --for pod/<NEW-STOREFRONT-POD>
   kubectl rollout undo deployment/storefront
   kubectl rollout status deployment/storefront
   kubectl get pods -l app=storefront
   ```
   The new pod is `ErrImagePull`, but the old ones keep serving (`200`): a bad image stalls a rolling update, it doesn't take the site down. The event: `Failed to pull image "nginx:1.29.88": ... NotFound`. After undo, kubectl warns that `last-applied-configuration` isn't updated: the lasting fix is the right tag in git.

9. ImagePullBackOff, cause 2: no credentials for a private registry.
   ```bash
   kubectl apply -f staged/admin.yaml
   sleep 40
   kubectl get pods -l app=admin
   kubectl events --for pod/<ADMIN-POD> | grep -i failed
   ```
   Same status, different message: the pull is denied (authorization failed / no basic auth credentials), not "not found". Read the message, not just the status. The fix:
   ```bash
   kubectl create secret docker-registry regcred --docker-server=localhost:5001 --docker-username=ci-bot --docker-password=demo-registry-pass-123
   kubectl patch deployment admin -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"regcred"}]}}}}'
   kubectl rollout status deployment/admin
   kubectl get pods -l app=admin
   ```

10. CreateContainerConfigError: a missing Secret.
    ```bash
    kubectl apply -f staged/mailer.yaml
    sleep 30
    kubectl get pod mailer
    kubectl describe pod mailer | grep -A2 -E '^ +State:'
    kubectl events --for pod/mailer | tail -2
    kubectl create secret generic mailer-smtp --from-literal=password=demo-smtp-pass-123
    sleep 15; kubectl get pod mailer
    ```
    `State: Waiting, Reason: CreateContainerConfigError`, `Error: secret "mailer-smtp" not found`, no logs (the container never existed). After creating the Secret, the kubelet retries by itself: `Running`, 0 restarts.

11. OOMKilled, and why `--previous` matters.
    ```bash
    kubectl apply -f staged/thumbnailer.yaml
    ```
    Wait a few minutes, then right after a restart:
    ```bash
    kubectl get pod <THUMBNAILER-POD>
    kubectl describe pod <THUMBNAILER-POD> | grep -A5 'Last State'
    kubectl logs <THUMBNAILER-POD> --previous | tail -3
    ```
    `Last State: Terminated, Reason: OOMKilled, Exit Code: 137`; the previous run's log ends near `thumbnail cache: 58 MiB`. Plain `logs` would show the new run.

12. Pending, three ways.
    ```bash
    kubectl apply -f staged/report.yaml -f staged/transcoder.yaml -f staged/uploads.yaml
    sleep 20
    kubectl get pods report transcoder uploads
    kubectl get pvc uploads
    kubectl events --for pod/report
    kubectl events --for pod/transcoder
    kubectl events --for pod/uploads
    kubectl events --for pvc/uploads
    kubectl get storageclass
    kubectl describe nodes | grep -E '^Name:|^Taints:|^  cpu:'
    kubectl describe node lab-worker | grep -A4 'Allocated resources'
    ```
    - `report`: `0/2 nodes are available: 1 Insufficient cpu, 1 node(s) had untolerated taint(s)` - it requests 20 CPUs.
    - `transcoder`: `1 node(s) didn't match Pod's node affinity/selector` - it wants `disktype: ssd`.
    - `uploads`: `pod has unbound immediate PersistentVolumeClaims`; the claim says `storageclass.storage.k8s.io "fast-ssd" not found`, and the cluster only has `standard`.

    If the worker really had an SSD, label it:
    ```bash
    kubectl label node lab-worker disktype=ssd
    sleep 10; kubectl get pod transcoder -o wide
    ```

13. Running but not ready: a probe on the wrong port.
    ```bash
    kubectl apply -f staged/catalog.yaml -f staged/search.yaml
    sleep 40
    kubectl get pods -l app=catalog
    kubectl get endpointslices -l kubernetes.io/service-name=catalog
    kubectl exec probe -- curl -s -m 5 catalog/courses; echo "exit $?"
    kubectl events --for pod/<CATALOG-POD> | tail -2
    kubectl get endpointslices -l kubernetes.io/service-name=catalog -o yaml | grep -A3 conditions
    ```
    `0/1 Running`, no restarts; the slice lists both IPs, but `ready: false, serving: false`; curl `exit 7`; the event: `Readiness probe failed: ... :8081/healthz ... connection refused`. Fix:
    ```bash
    kubectl patch deployment catalog --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":"http"}]'
    kubectl rollout status deployment/catalog
    kubectl exec probe -- curl -s catalog/courses; echo
    ```

14. Healthy pods, no traffic: a selector mismatch.
    ```bash
    kubectl get pods -l app=search
    kubectl get endpointslices -l kubernetes.io/service-name=search
    kubectl describe service search | grep -E 'Selector|Endpoints'
    kubectl get pods --show-labels -l app=search
    kubectl patch service search -p '{"spec":{"selector":{"app":"search"}}}'
    kubectl get endpointslices -l kubernetes.io/service-name=search
    kubectl exec probe -- curl -s search/courses; echo
    ```
    Pods `1/1`, but the slice is `<unset>`; `Selector: app=search-api` vs pods `app=search`. After the patch, both pod IPs on 8080.

15. Names across namespaces.
    ```bash
    kubectl -n ops exec dns-check -- curl -s -m 5 api/courses; echo "exit $?"
    kubectl -n ops exec dns-check -- grep search /etc/resolv.conf
    kubectl -n ops exec dns-check -- nslookup api
    kubectl -n ops exec dns-check -- nslookup api.allcsvideos
    kubectl -n ops exec dns-check -- curl -s api.allcsvideos/courses; echo
    ```
    `exit 6` (could not resolve host); the search list starts with `ops.svc.cluster.local`; `api` is `NXDOMAIN`; `api.allcsvideos` resolves and answers.

16. A NetworkPolicy (kind enforces them since v0.24.0).
    ```bash
    kubectl apply -f staged/deny-api.yaml
    kubectl exec probe -- curl -s -m 5 -o /dev/null -w '%{http_code}\n' storefront/api/courses; echo "exit $?"
    kubectl get pods -l app=api
    kubectl get endpointslices -l kubernetes.io/service-name=api
    kubectl get networkpolicy
    kubectl describe networkpolicy api-ingress | sed -n '/Spec:/,$p'
    kubectl apply -f staged/allow-storefront.yaml
    kubectl exec probe -- curl -s storefront/api/courses; echo
    kubectl exec probe -- curl -s -m 5 api/courses; echo "exit $?"
    ```
    `000` / `exit 28` while pods and endpoints look perfect - the sign to check policies. Ingress is allowed only from `app=admin`. After the fix the storefront answers, and `probe` (still not allowed) still times out.

17. Look inside a distroless container.
    ```bash
    kubectl exec -it <API-POD> -- sh
    kubectl debug -it <API-POD> --image=busybox:1.37.0 --target=api -- sh
    ```
    `exec` fails (`executable file not found`). In the debug shell:
    ```bash
    ps
    wget -qO- localhost:8080/healthz; echo
    ls /proc/1/root/app
    exit
    ```
    `python3 -u /app/app.py` is PID 1 (user 65532), `{"status": "ok"}`, and `app.py`. The ephemeral container stays in the pod spec:
    ```bash
    kubectl get pod <API-POD> -o jsonpath='{.spec.ephemeralContainers[*].name}'; echo
    ```

18. Debug the node, and port-forward.
    ```bash
    kubectl debug node/lab-worker -it --image=busybox:1.37.0 -- chroot /host crictl ps --name api
    kubectl get pods | grep node-debugger
    kubectl delete pod <NODE-DEBUGGER-POD>
    kubectl port-forward deployment/api 18086:8080 &
    sleep 2; curl -s localhost:18086/courses; echo
    kill %1
    ```
    The node's own crictl lists the two API containers; the debugger pod stays `Completed` until you delete it; port-forward reaches a pod with nothing in between.

19. Step 6, check the cluster.
    ```bash
    kubectl get nodes
    kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -6
    kubectl -n kube-system get pods
    ```
    When unrelated pods (and CoreDNS) fail probes the same way, suspect the node, not the pods. In the video, a busy laptop showed restarts of the API server, scheduler and controller manager in `kube-system`.

## Status cheat sheet
| Status | First command | Usual causes |
|---|---|---|
| Pending | `kubectl events --for pod/X` | Not enough CPU/memory, selector or taint mismatch, unbound claim |
| ErrImagePull / ImagePullBackOff | `kubectl events --for pod/X` | Wrong name or tag (not found), missing credentials (denied) |
| CreateContainerConfigError | `kubectl events --for pod/X` | Missing ConfigMap, Secret or key |
| CrashLoopBackOff / Error | `kubectl logs X --previous` | Bad setting, app bug |
| OOMKilled (137) | `kubectl describe pod X` (Last State) | A leak, or a limit too low |
| Running, 0/1 ready | `kubectl describe pod X` (probe events) | Wrong probe port or path |
| Healthy pods, no traffic | EndpointSlices, then DNS, then NetworkPolicies | Selector mismatch, wrong name, policy |

## Common mistakes
- **Deleting pods instead of reading events.** The replacements have the same problem, and the evidence goes with the old ones.
- **Reading only the top of `describe`.** The answer is at the bottom (events) and in Last State.
- **Forgetting `--previous`.** Once a new container runs, plain `logs` shows a fresh start.
- **Restarting to fix config errors.** Fix the ConfigMap or Secret first, then restart once, on purpose.
- **No timeline.** Write down what you saw and changed, with times.
- **Guessing instead of walking the path.** Healthy pods with no traffic is a Service, DNS or policy problem: check each hop in order.

## Clean up
From the lesson folder (one level above `manifests/`):
```bash
bash lab/down.sh
```

## Next
[M15-L01 · Helm](../m15-l01-helm/)
