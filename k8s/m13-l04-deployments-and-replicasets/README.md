# M13-L04 · Deployments and ReplicaSets
> Video: Module 13, Lesson 4. Watch it first, then follow along here.

## What you'll learn
- How a Deployment owns ReplicaSets and a ReplicaSet owns pods: selectors, the `pod-template-hash` label and `ownerReferences`.
- Why a Deployment's pods come back after a node dies, and a bare pod doesn't.
- Scaling (imperative vs declarative) and why only a template change creates a new ReplicaSet.
- Rolling updates under real traffic: `maxSurge`, `maxUnavailable`, and why a readiness probe makes "ready" mean ready.
- Rollout controls: `minReadySeconds`, `progressDeadlineSeconds`, `revisionHistoryLimit`, change-cause, `rollout undo`, pause/resume.
- The Recreate strategy and the downtime it causes.

## Before you start
- Docker Desktop (or Docker Engine on Linux), kind **v0.33.0**, kubectl **v1.37.1**. Optional: `jq`.
- Node image `kindest/node:v1.37.0` (Kubernetes 1.37.0), pinned in `kind-cluster.yaml`.
- Pods and kubectl basics from [M13-L03](../m13-l03-pods/) and [M13-L02](../m13-l02-your-first-cluster/).
- Several steps use two or three terminals at once: one to watch, one for the traffic generator, one for commands. Open all of them in this folder.

## Files in this folder
| File | What it is |
|---|---|
| `kind-cluster.yaml` | Cluster `lab`: one control plane, two workers, pinned node image |
| `app/app.py`, `app/Dockerfile` | Storefront in Python: 4 s warm-up, `/healthz/ready`, answers carry `X-App-Version` and `X-Pod`, drains 3 s on SIGTERM. Built as 1.0.0, 2.0.0 and 3.0.0 (3.0.0 is a staged bad build that is never ready) |
| `traffic/traffic.py`, `traffic/Dockerfile` | Simulated users: 20 requests/s to a URL, prints one line per second (answers per version, errors, pods) |
| `manifests/web-v1.yaml` ... `web-v7.yaml` | The `web` Deployment at each stage of the lesson (you copy each one to `web.yaml`) |
| `manifests/web-v7-bad.yaml` | Recreate strategy with a leftover `rollingUpdate` block (rejected on purpose) |
| `manifests/web-bad-selector.yaml` | A Deployment whose selector doesn't match its template labels (rejected on purpose) |
| `manifests/svc.yaml` | ClusterIP Service `web`: port 80 -> pod port 8080 |
| `manifests/traffic.yaml` | Deployment that runs the traffic generator image |
| `manifests/hook/web-pod.yaml`, `web-deploy.yaml` | Bare pod vs Deployment, for the node-failure demo |

| Stage | What changes |
|---|---|
| `web-v1.yaml` | 4 replicas, image 1.0.0, default 25% / 25% strategy written out |
| `web-v2.yaml` | replicas 6 |
| `web-v3.yaml` | + readinessProbe `GET /healthz/ready` every 2 s (image 1.0.0) |
| `web-v4.yaml` | maxSurge 1, maxUnavailable 0, image 2.0.0 |
| `web-v5.yaml` | maxSurge 0, maxUnavailable 50%, image 1.0.0 |
| `web-v6.yaml` | change-cause annotation, minReadySeconds 5, progressDeadlineSeconds 30, revisionHistoryLimit 4, surge 1 / unavailable 0, image 2.0.0 |
| `web-v7.yaml` | strategy Recreate, image 1.0.0 |

## Follow along

1. Create the cluster, build four images, load them into the nodes, and make a namespace the default.
   ```bash
   kind create cluster --config kind-cluster.yaml
   for v in 1.0.0 2.0.0 3.0.0; do docker build -q --build-arg APP_VERSION=$v -t web:$v app; done
   docker build -q -t traffic:1.0 traffic
   kind load docker-image web:1.0.0 web:2.0.0 web:3.0.0 traffic:1.0 --name lab
   kubectl create namespace allcsvideos
   kubectl config set-context --current --namespace=allcsvideos
   kubectl get nodes
   ```

2. **The node-failure demo (about 7 minutes).** A bare pod and a Deployment's pod on the same dying node. Run it in its own namespace, `hook`:
   ```bash
   kubectl create namespace hook
   kubectl apply -n hook -f manifests/hook/
   kubectl get pods -n hook -o wide
   ```
   Note which worker runs the bare pod `web` (call it `<NODE>`; it was `lab-worker` in the video). In a second terminal: `kubectl get pods -n hook -o wide -w`. Then stop that node:
   ```bash
   date +%T; docker stop <NODE>
   kubectl get nodes
   ```
   Within a minute the node is `NotReady`. For five minutes nothing changes. Then both pods on that node turn `Terminating`, and the Deployment creates a replacement on the other worker in the same second:
   ```bash
   kubectl get pods -n hook -o wide
   ```
   ```
   NAME                   READY   STATUS        ...   NODE
   web                    1/1     Terminating   ...   lab-worker
   web-5b5f558d69-dc79m   1/1     Running       ...   lab-worker2
   web-5b5f558d69-l7w44   1/1     Terminating   ...   lab-worker
   web-5b5f558d69-z8fdv   1/1     Running       ...   lab-worker2
   ```
   Bring the node back. The bare pod is deleted for good:
   ```bash
   docker start <NODE>
   kubectl get pods -n hook -o wide
   kubectl get pod web -n hook
   kubectl delete namespace hook
   ```
   `Error from server (NotFound): pods "web" not found`. (If the bare pod and a Deployment pod didn't share a node, delete the namespace and try again.)

3. Your first Deployment. Read `manifests/web-v1.yaml` (replicas, selector, strategy, template), then:
   ```bash
   cp manifests/web-v1.yaml web.yaml
   kubectl apply -f web.yaml
   kubectl rollout status deployment web
   kubectl get deploy,rs,pods -o wide
   ```
   You should see:
   ```
   deployment.apps/web   4/4     4            4           5s    web          web:1.0.0   app=web
   replicaset.apps/web-67956dbd68   4         4         4       4s    web          web:1.0.0   app=web,pod-template-hash=67956dbd68
   pod/web-67956dbd68-7ptcm   1/1     Running   0          4s    10.244.2.4   lab-worker2   ...
   ...
   ```
   Your hash and pod names will differ; use yours in later commands.

4. Labels and owners.
   ```bash
   kubectl get rs,pods --show-labels
   kubectl get rs <RS-NAME> -o jsonpath='{.metadata.ownerReferences}' | jq
   kubectl get pod <POD-NAME> -o jsonpath='{.metadata.ownerReferences}' | jq
   ```
   Every pod has `app=web,pod-template-hash=67956dbd68`. The ReplicaSet's owner is `"kind": "Deployment", "name": "web"`; the pod's owner is the ReplicaSet, both with `"controller": true`.

5. Two mistakes the API server refuses.
   ```bash
   kubectl apply -f manifests/web-bad-selector.yaml
   sed 's/app: web/app: web2/' web.yaml | kubectl apply -f -
   ```
   You should see:
   ```
   The Deployment "web-typo" is invalid: spec.template.metadata.labels: Invalid value: {"app":"storefront"}: `selector` does not match template `labels`
   The Deployment "web" is invalid: spec.selector: Invalid value: {"matchLabels":{"app":"web2"}}: field is immutable
   ```

6. The ReplicaSet at work. Terminal 2: `kubectl get pods -w`. Terminal 1:
   ```bash
   kubectl delete pod <POD-NAME>
   kubectl get rs
   ```
   In the same second the pod is `Terminating` and a replacement is `Pending`; `4 4 4` again. Now change the ReplicaSet directly (terminal 2: `kubectl get rs -w`):
   ```bash
   kubectl scale rs <RS-NAME> --replicas=6
   kubectl get rs
   ```
   The watch shows desired `6`, then `4` again in the same second. The Deployment owns the ReplicaSet and says 4, so it puts it back. Never manage a Deployment's ReplicaSets yourself.

7. Scaling: imperative, then declarative.
   ```bash
   kubectl scale deployment web --replicas=6
   kubectl get deploy web
   kubectl diff -f web.yaml
   ```
   The diff shows live `replicas: 6` vs the file's `4`, plus two server defaults: `progressDeadlineSeconds: 600` and `revisionHistoryLimit: 10`. Put the new number in the file:
   ```bash
   cp manifests/web-v2.yaml web.yaml
   kubectl apply -f web.yaml
   kubectl diff -f web.yaml; echo "diff exit code: $?"
   ```
   `diff exit code: 0`. Scale to zero and back:
   ```bash
   kubectl scale deployment web --replicas=0
   kubectl get deploy,rs,pods
   kubectl apply -f web.yaml
   kubectl rollout status deployment web
   kubectl get rs
   ```
   `0/0`, then six again, with the **same** ReplicaSet. Scaling never creates a new ReplicaSet; only a template change does.

8. Add a Service and the simulated users.
   ```bash
   kubectl apply -f manifests/svc.yaml -f manifests/traffic.yaml
   kubectl get svc web
   kubectl rollout status deployment traffic
   kubectl exec deploy/traffic -- python traffic.py http://web 3 /tmp/test
   ```
   You should see:
   ```
   06:38:20 1.0.0=20 err=0 pods=5
   06:38:21 1.0.0=20 err=0 pods=5
   06:38:22 1.0.0=15 err=0 pods=6
   done: 60 requests, 0 failed
   ```

9. **Rollout 1, without a readiness probe.** For every rollout from here on use three terminals:
   - terminal 2: `kubectl get rs -w`
   - terminal 3: `kubectl exec deploy/traffic -- python traffic.py http://web 45 /tmp/run` (start it a few seconds before the change)
   - terminal 1: the rollout commands

   ```bash
   kubectl set image deployment/web web=web:2.0.0
   kubectl rollout status deployment web
   ```
   The new ReplicaSet scales to 2 (the surge), the old one drops to 5, then fast to 0. But the pods count as ready after about two seconds while the app needs four to listen, so the traffic shows errors. In the video: `done: 640 requests, 94 failed` - and rollout status still said `successfully rolled out`.

10. **Rollout 2, with a readiness probe.** `web-v3.yaml` adds the probe. Diff first:
    ```bash
    cp manifests/web-v3.yaml web.yaml
    kubectl diff -f web.yaml | grep -E '^[+-] '
    ```
    The probe is added - and the image goes from `web:2.0.0` back to `web:1.0.0`, because `set image` was imperative and the file still says 1.0.0. Drift. Apply it anyway (traffic running):
    ```bash
    kubectl apply -f web.yaml
    kubectl rollout status deployment web
    ```
    New pods take about five seconds to become ready, and only then do old pods go. `done: 900 requests, 0 failed`.

11. The two numbers.
    ```bash
    kubectl explain deploy.spec.strategy.rollingUpdate.maxSurge | sed -n '/DESCRIPTION/,/Example/p'
    kubectl explain deploy.spec.strategy.rollingUpdate.maxUnavailable | sed -n '/DESCRIPTION/,/Example/p'
    ```
    maxSurge rounds up, maxUnavailable rounds down, both default to 25%, and they can't both be 0.

    Setting one, surge 1 / unavailable 0, to 2.0.0 (traffic running):
    ```bash
    cp manifests/web-v4.yaml web.yaml
    kubectl apply -f web.yaml
    time kubectl rollout status deployment web
    ```
    One pod at a time, `real 0m38s`, `0 failed`. Setting two, surge 0 / unavailable 50%, back to 1.0.0 (traffic running):
    ```bash
    cp manifests/web-v5.yaml web.yaml
    kubectl apply -f web.yaml
    time kubectl rollout status deployment web
    ```
    About 12 s, also `0 failed`, but for about ten seconds only three pods answer (`pods=3`): half the capacity.

12. Rollout history and safer settings.
    ```bash
    kubectl rollout history deployment web
    ```
    Revisions `1 2 4 5`, every CHANGE-CAUSE `<none>`. Revision 3 is missing: going back to the same template reused its ReplicaSet under the new number 5. Now `web-v6.yaml` adds a change-cause, `minReadySeconds: 5`, `progressDeadlineSeconds: 30` and `revisionHistoryLimit: 4`:
    ```bash
    cp manifests/web-v6.yaml web.yaml
    kubectl apply -f web.yaml
    time kubectl rollout status deployment web
    kubectl rollout history deployment web
    ```
    It takes about 1 m 44 s (against 38 s before). History shows `6  2.0.0: new course page (PR #214)`.

13. **The staged bad release** (3.0.0, never ready). Traffic running, rs watch running:
    ```bash
    kubectl set image deployment/web web=web:3.0.0 --record
    kubectl rollout status deployment web; echo "exit code: $?"
    ```
    You should see:
    ```
    Flag --record has been deprecated, --record will be removed in the future
    deployment.apps/web image updated
    Waiting for deployment "web" rollout to finish: 1 out of 6 new replicas have been updated...
    error: deployment "web" exceeded its progress deadline
    exit code: 1
    ```
    And the users: `done: 1100 requests, 0 failed`. Find out why:
    ```bash
    kubectl get deploy web
    kubectl get pods -l app=web
    kubectl describe deployment web | grep -A4 Conditions
    kubectl logs <THE-0/1-POD>
    kubectl events --for pod/<THE-0/1-POD> | grep -i readiness
    kubectl rollout history deployment web
    ```
    Six 2.0.0 pods plus one `0/1 Running` pod; `Progressing False ProgressDeadlineExceeded`; the log says `ERROR catalog config missing: CATALOG_URL is not set`; the probe failed with `connection refused`, then `statuscode: 503`. Revision 7's change-cause is the whole `kubectl set image ... --record=true` command.

14. Roll back.
    ```bash
    kubectl rollout undo deployment web
    kubectl rollout status deployment web
    kubectl get pods -l app=web
    kubectl rollout history deployment web
    ```
    Instant, because the 2.0.0 pods were never touched; 2.0.0 comes back as revision 8. Note the warning: `undo` doesn't update `last-applied-configuration`, so after an emergency undo put the good version in git and apply that. Go further back:
    ```bash
    kubectl rollout history deployment web --revision=5
    kubectl rollout undo deployment web --to-revision=5
    time kubectl rollout status deployment web >/dev/null
    kubectl rollout history deployment web
    ```
    Revision 5 is 1.0.0 with the probe; it comes back as revision 9 (about 1 m 38 s).

15. Pause, make several changes, resume once.
    ```bash
    kubectl rollout pause deployment web
    kubectl set image deployment/web web=web:2.0.0
    kubectl set resources deployment web --requests=cpu=50m,memory=32Mi --limits=memory=64Mi
    kubectl annotate deployment web kubernetes.io/change-cause="2.0.0 with resource requests" --overwrite
    kubectl get rs -l app=web
    kubectl rollout resume deployment web
    kubectl rollout status deployment web >/dev/null && echo rolled out
    kubectl rollout history deployment web
    kubectl get rs -l app=web
    ```
    While paused: no new ReplicaSet. After resume: one rollout for all three changes, revision 11, and only five ReplicaSets left (current + 4 old, `revisionHistoryLimit: 4`). Revision 1 is gone, and so is the chance to roll back to it.

16. **Recreate** (staged downtime). First the leftover `rollingUpdate` block is rejected:
    ```bash
    cp manifests/web-v7-bad.yaml web.yaml
    kubectl apply -f web.yaml
    ```
    `spec.strategy.rollingUpdate: Forbidden: may not be specified when strategy 'type' is 'Recreate'`. Then the fixed file (traffic + rs watch running):
    ```bash
    cp manifests/web-v7.yaml web.yaml
    kubectl apply -f web.yaml
    kubectl rollout status deployment web
    ```
    The old ReplicaSet goes to 0, the new one appears only once the old pods are gone: about sixteen seconds of errors. `done: 700 requests, 319 failed`.

17. Reusing a tag does nothing; `rollout restart` forces new pods.
    ```bash
    kubectl set image deployment/web web=web:1.0.0
    kubectl apply -f web.yaml
    kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[0].imagePullPolicy}{"\n"}'
    kubectl rollout restart deployment web
    kubectl get rs -l app=web
    kubectl get deploy web -o jsonpath='{.spec.template.metadata.annotations}{"\n"}'
    ```
    `set image` prints nothing, apply says `unchanged`, the pull policy is `IfNotPresent`. After the restart a new ReplicaSet appears, and the template carries `{"kubectl.kubernetes.io/restartedAt":"..."}`.

## Common mistakes
- **Selector vs template labels.** They must match, and the selector is immutable. Plan your labels before the first apply.
- **Reusing an image tag.** A new build under an old tag never rolls out, and with `IfNotPresent` nodes keep the old image. Give every build a new tag (`latest` is worse).
- **No readiness probe.** 94 failed requests, and a rollout that called itself a success.
- **`kubectl edit`, `set image` and `undo` in production.** They work, and they create drift from git. Use them in an emergency, then commit the same change.
- **Forgetting the change-cause.** A history full of `<none>` is useless at 3 a.m. Put the reason in the file.
- **Thinking a rollback undoes everything.** It restores the pod template only - not a database migration, not a sent email (module 9, lesson 4: expand and contract).

## Clean up
```bash
rm -f web.yaml
kind delete cluster --name lab
docker rmi web:1.0.0 web:2.0.0 web:3.0.0 traffic:1.0
```

## Next
[M13-L05 · Services and DNS](../m13-l05-services-and-dns/)
