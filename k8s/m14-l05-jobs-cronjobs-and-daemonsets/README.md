# M14-L05 · Jobs, CronJobs and DaemonSets
> Video: Module 14, Lesson 5. Watch it first, then follow along here.

## What you'll learn
- Why a Deployment is the wrong tool for work that finishes (a successful migration ends in CrashLoopBackOff).
- Jobs: completions, parallelism, Indexed mode, `backoffLimit` and back-off timing, `activeDeadlineSeconds`, `podFailurePolicy`, and `ttlSecondsAfterFinished`.
- CronJobs: the five-field schedule, `timeZone`, running one by hand, and what `Allow`, `Forbid` and `Replace` really do when runs overlap.
- DaemonSets: one pod per matching node, taints and tolerations, `nodeSelector`, and node-by-node rolling updates.
- Static pods and mirror pods on the control plane.

## Before you start
- Docker Desktop (or Docker Engine on Linux), kind **v0.33.0**, kubectl **v1.37.1**, `jq`.
- Node image `kindest/node:v1.37.0` (Kubernetes 1.37.0), pinned in `kind-cluster.yaml`.
- Deployments from [M13-L04](../m13-l04-deployments-and-replicasets/), cron syntax from module 3.
- Some steps take several minutes of real time (back-offs, the every-minute CronJobs). Timestamps will differ on your machine.

## Files in this folder
| File | What it is |
|---|---|
| `kind-cluster.yaml` | Cluster `lab`: one control plane, two workers; leader election off (single control plane, lab only) |
| `manifests/ns.yaml` | Namespace `allcsvideos` |
| `manifests/migrate-deploy.yaml` | Staged mistake: a one-off migration as a Deployment |
| `manifests/migrate-job.yaml` | The migration as a Job: `backoffLimit: 2`, `activeDeadlineSeconds: 120`, `ttlSecondsAfterFinished: 60` |
| `manifests/thumbs.yaml` | Indexed Job: 6 completions, parallelism 3 |
| `manifests/fail-never.yaml`, `fail-onfailure.yaml` | A report that always exits 1, with `restartPolicy` Never vs OnFailure, `backoffLimit: 3` |
| `manifests/deadline.yaml`, `pfp.yaml` | A hung transcode with a 20 s deadline; a Pod failure policy that fails the Job on exit code 42 |
| `manifests/report-cron.yaml` | Nightly report CronJob: `30 2 * * *`, `timeZone: Asia/Kolkata`, Forbid |
| `manifests/transcode-allow.yaml`, `-forbid.yaml`, `-replace.yaml` | A 90 s job every minute, one per concurrency policy |
| `manifests/transcode-deadline.yaml` | The same with Forbid and `startingDeadlineSeconds: 20` |
| `manifests/log-agent.yaml`, `tol-patch.yaml` | Demo log-agent DaemonSet (read-only hostPath `/var/log/pods`) and a toleration patch for the control plane |
| `manifests/transcode-agent.yaml` | DaemonSet only on nodes labelled `allcsvideos.com/transcode=true` |

## Follow along

1. Cluster and namespace.
   ```bash
   kind create cluster --config kind-cluster.yaml
   kubectl get nodes
   kubectl apply -f manifests/ns.yaml
   kubectl config set-context --current --namespace allcsvideos
   ```

2. **The hook: a migration as a Deployment.** Terminal 2: `kubectl get pods -w`. Terminal 1:
   ```bash
   kubectl apply -f manifests/migrate-deploy.yaml
   ```
   Watch for about 2 minutes: `Completed`, then `Running` again (restart 1), then `CrashLoopBackOff` - success is treated like a crash. Then:
   ```bash
   kubectl get pods
   kubectl logs deploy/migrate
   kubectl events | grep -E 'Started|BackOff'
   kubectl delete -f manifests/migrate-deploy.yaml
   ```
   `Container started` x5, `Back-off restarting failed container` x4: the migration ran five times.

3. The right tool: a Job.
   ```bash
   kubectl apply -f manifests/migrate-job.yaml
   kubectl wait --for=condition=complete job/migrate --timeout=120s; echo exit code $?
   kubectl get job,pods
   kubectl logs job/migrate
   kubectl get job migrate -o jsonpath='{.status.completionTime}{"\n"}'
   ```
   You should see:
   ```
   job.batch/migrate condition met
   exit code 0
   job.batch/migrate   Complete   1/1           7s         7s
   pod/migrate-cwmw2   0/1     Completed   0          7s
   applying migration 0042_add_lesson_tags
   done
   ```
   `kubectl wait --for=condition=complete` is the line a deploy pipeline waits on before rolling out the new version.

4. The TTL cleans up. Within a minute of completion:
   ```bash
   kubectl get jobs -w --output-watch-events
   ```
   Exactly 60 s after `completionTime`: `MODIFIED`, then `DELETED`. Ctrl+C, then `kubectl get job,pods` says `No resources found`.

5. Parallel work with an Indexed Job. Terminal 2: `kubectl get pods -w`. Terminal 1:
   ```bash
   kubectl apply -f manifests/thumbs.yaml
   ```
   Three pods start (`thumbs-0`, `-1`, `-2`); as each finishes, the next index starts - never more than three at once. Then:
   ```bash
   kubectl get job thumbs
   kubectl get pods -L batch.kubernetes.io/job-completion-index
   kubectl logs -l app=thumbs --tail=-1 | sort
   ```
   `Complete 6/6` in about 36 s (78 s of sleep in total), and lessons 1 to 6, each exactly once.

6. Retries and back-off: Never vs OnFailure. Terminal 2: `kubectl get pods -w`. Terminal 1:
   ```bash
   kubectl apply -f manifests/fail-never.yaml -f manifests/fail-onfailure.yaml
   ```
   Wait about 2.5 minutes. With Never, a new pod after 10 s, 20 s, then 40 s (four in total); with OnFailure, one pod restarted in place, then deleted when the Job gives up. Then:
   ```bash
   kubectl get jobs
   kubectl get pods
   kubectl logs <ONE-REPORT-NEVER-POD>
   kubectl get job report-never -o jsonpath='{.status.conditions[?(@.type=="Failed")]}' | jq .
   kubectl events --for job/report-never
   kubectl logs job/report-onfailure
   ```
   Both `Failed 0/1`; four `report-never-*` pods in `Error` with their logs (`ERROR: database not reachable`); `"reason": "BackoffLimitExceeded"`. The OnFailure Job's logs are gone (`timed out waiting`) - use Never while you debug.

7. Deadlines and pod failure policies. Terminal 2: `kubectl get jobs -w`. Terminal 1:
   ```bash
   kubectl apply -f manifests/deadline.yaml -f manifests/pfp.yaml
   sleep 35
   kubectl get pods
   kubectl get jobs -o custom-columns=NAME:.metadata.name,REASON:.status.conditions[-1].reason,MESSAGE:.status.conditions[-1].message
   ```
   You should see:
   ```
   NAME               REASON             MESSAGE
   report-badconfig   PodFailurePolicy   Container report for pod allcsvideos/report-badconfig-p9w7f failed with exit code 42 matching FailJob rule at index 0
   transcode-hung     DeadlineExceeded   Job was active longer than specified deadline
   ```
   The hung pod shows `Terminating` for up to 30 s: its script ignores SIGTERM, so the kubelet waits out the grace period.

8. Every-minute CronJobs that always overrun (they need about 6 minutes; start them now). Terminal 2: `kubectl get jobs -w`. Terminal 1:
   ```bash
   kubectl apply -f manifests/transcode-allow.yaml -f manifests/transcode-forbid.yaml -f manifests/transcode-replace.yaml
   kubectl get cronjobs
   ```

9. Meanwhile, the nightly report.
   ```bash
   kubectl apply -f manifests/report-cron.yaml
   kubectl get cronjob report
   kubectl create job --from=cronjob/report report-manual-1
   kubectl wait --for=condition=complete job/report-manual-1 --timeout=60s
   kubectl logs job/report-manual-1
   kubectl get job report-manual-1 -o jsonpath='{.metadata.annotations}' | jq .
   kubectl create cronjob tz-test --image=busybox:1.37.0 --schedule='CRON_TZ=Asia/Kolkata 30 2 * * *' --dry-run=server -- date
   ```
   `30 2 * * *   Asia/Kolkata   False   0   <none>`; the manual run prints `nightly sales report: 41 new students` and carries `"cronjob.kubernetes.io/instantiate": "manual"`. The CRON_TZ prefix is rejected: `cannot use TZ or CRON_TZ in schedule` - use the `timeZone` field.

10. After about 6 minutes, compare the three policies.
    ```bash
    kubectl get cronjobs
    kubectl get jobs -o custom-columns='JOB:.metadata.name,SCHEDULED:.metadata.annotations.batch\.kubernetes\.io/cronjob-scheduled-timestamp,STARTED:.status.startTime,FINISHED:.status.completionTime,STATUS:.status.conditions[-1].type' --sort-by=.metadata.creationTimestamp
    kubectl events --for cronjob/transcode-replace | tail -6
    kubectl events --for cronjob/transcode-forbid
    ```
    - **Allow** starts every minute on time; two overlap half of each minute.
    - **Forbid** never overlaps: a run starts late (the moment the previous one ends), and some schedule times are skipped (`JobAlreadyActive ... concurrency policy is Forbid`).
    - **Replace** starts on time and deletes the running Job (`Deleted job ...` / `Created job ...`): no Replace transcode ever finishes.

11. Suspend, clean up, and the starting deadline.
    ```bash
    kubectl patch cronjob transcode-allow transcode-forbid transcode-replace -p '{"spec":{"suspend":true}}'
    kubectl get cronjobs
    kubectl delete cronjob transcode-allow transcode-forbid transcode-replace
    kubectl apply -f manifests/transcode-deadline.yaml
    ```
    `SUSPEND True`, but running Jobs carry on (`ACTIVE 1`). With `startingDeadlineSeconds: 20`, a run that would start more than 20 s late is skipped instead. Watch it for a few minutes with `kubectl get jobs -w` if you like, then `kubectl delete -f manifests/transcode-deadline.yaml`.

12. DaemonSets: the ones you already have, then a log agent.
    ```bash
    kubectl get daemonsets -A
    kubectl apply -f manifests/log-agent.yaml
    kubectl rollout status ds/log-agent
    kubectl get ds log-agent
    kubectl get pods -l app=log-agent -o wide
    ```
    `kindnet` and `kube-proxy`: 3 of 3. `log-agent`: only `2` - one on each worker, none on the control plane.

13. Why not the control plane? And what does each agent see?
    ```bash
    kubectl describe node lab-control-plane | grep Taints
    kubectl get ds kube-proxy -n kube-system -o jsonpath='{.spec.template.spec.tolerations}' | jq -c .
    kubectl logs -l app=log-agent --prefix --tail=1
    kubectl exec <A-LOG-AGENT-POD> -- ls /var/log/pods
    kubectl exec <A-LOG-AGENT-POD> -- touch /var/log/pods/hello
    ```
    `node-role.kubernetes.io/control-plane:NoSchedule`; kube-proxy tolerates everything (`[{"operator":"Exists"}]`). Each agent sees only its own node's pod log folders, and `touch` fails: `Read-only file system`.

14. Cover the control plane with a toleration. Terminal 2: `kubectl get pods -l app=log-agent -o wide -w`. Terminal 1:
    ```bash
    kubectl patch ds log-agent --patch-file manifests/tol-patch.yaml
    kubectl rollout status ds/log-agent
    kubectl get pods -l app=log-agent -o wide
    ```
    A pod appears on `lab-control-plane` and the others are replaced one at a time: 3 pods, one per node.

15. Only on labelled nodes.
    ```bash
    kubectl apply -f manifests/transcode-agent.yaml
    kubectl get ds transcode-agent
    kubectl label node lab-worker2 allcsvideos.com/transcode=true
    kubectl rollout status ds/transcode-agent
    kubectl get pods -l app=transcode-agent -o wide
    kubectl label node lab-worker2 allcsvideos.com/transcode-
    kubectl get ds transcode-agent; kubectl get pods -l app=transcode-agent
    ```
    `DESIRED 0`, then one pod on `lab-worker2`, then `Terminating` when the label is removed.

16. A rolling update, one node at a time. Terminal 2: `kubectl get pods -l app=log-agent -w`. Terminal 1:
    ```bash
    kubectl set env ds/log-agent AGENT_VERSION=2
    kubectl rollout status ds/log-agent
    kubectl logs -l app=log-agent --prefix --tail=1
    ```
    `1 out of 3 new pods have been updated...`, then 2, then done; every agent now logs `v2 on lab-...`.

17. Static pods and mirror pods.
    ```bash
    docker exec lab-control-plane ls -l /etc/kubernetes/manifests
    kubectl get pods -n kube-system --field-selector spec.nodeName=lab-control-plane
    kubectl delete pod -n kube-system kube-scheduler-lab-control-plane
    sleep 15; kubectl get pod -n kube-system kube-scheduler-lab-control-plane
    ```
    Four files (etcd, kube-apiserver, kube-controller-manager, kube-scheduler). The deleted mirror pod is back within seconds with `0` restarts: the static pod never stopped. For your own agents, use a DaemonSet.

## Common mistakes
- **A CronJob that isn't idempotent.** It may run twice (or not at all); the second run must not email or charge anyone twice.
- **`Allow` with a job that can overrun.** Runs pile up and fight over the same data. Pick Forbid or Replace on purpose.
- **Finished Jobs nobody deletes.** They sit in etcd and slow the API server. Set `ttlSecondsAfterFinished`, and history limits on CronJobs.
- **A DaemonSet without resource limits.** One leak, multiplied by every node. Small requests, firm memory limits.
- **Missing tolerations.** The agent quietly skips tainted nodes (control plane, GPU nodes), and nobody notices the missing logs.
- **A CronJob doing a queue's work.** Polling every minute is slow and wasteful. Use a queue with workers, or KEDA.
- **Running a migration in an init container.** It runs once per pod: ten replicas, ten migrations at once. Use a Job before the rollout.

## Clean up
```bash
kind delete cluster --name lab
```

## Next
[M14-L06 · Troubleshooting Kubernetes](../m14-l06-troubleshooting-kubernetes/)
