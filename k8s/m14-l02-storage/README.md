# M14-L02 · Storage
> Video: Module 14, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- How long data lives in each volume type: `emptyDir` (the pod), `hostPath` (one node), and a PersistentVolumeClaim (outlives every pod).
- The PV / PVC model: static provisioning by an admin, dynamic provisioning by a StorageClass, binding, and volume phases.
- StorageClass details that bite: `WaitForFirstConsumer`, access modes, (no) expansion, and `Delete` vs `Retain`.
- StatefulSets: stable pod names, one claim per pod, ordered start/stop, and a headless Service for per-pod DNS.
- What a StatefulSet does **not** give you: replication, failover or backups.

## Before you start
- Docker Desktop (or Docker Engine on Linux), kind **v0.33.0**, kubectl **v1.37.1**.
- Node image `kindest/node:v1.37.0` (Kubernetes 1.37.0), pinned in `kind-cluster.yaml`. kind ships the `standard` StorageClass (`rancher.io/local-path`).
- Secrets from [M13-L06](../m13-l06-configmaps-and-secrets/), headless Services from [M13-L05](../m13-l05-services-and-dns/).
- The database password in `db-creds.yaml` is a fake lab value.

## Files in this folder
| File | What it is |
|---|---|
| `kind-cluster.yaml` | Cluster `lab`: one control plane, two workers (`lab-worker`, `lab-worker2`) |
| `manifests/db-creds.yaml`, `catalog-seed.yaml` | Fake DB password; a seed script with three courses |
| `manifests/catalog-db.yaml` | The hook: PostgreSQL 18.6 as a Deployment with an `emptyDir` data volume |
| `manifests/hostpath-demo.yaml`, `hostpath-demo-b.yaml` | Pods `scratch-a` (on `lab-worker`) and `scratch-b` (on `lab-worker2`) with the same hostPath |
| `manifests/pv-static.yaml`, `pvc-static.yaml`, `pvc-too-big.yaml` | Static provisioning: a 2Gi PV (Retain, class `manual`), a 1Gi claim, a 5Gi claim that can't bind |
| `manifests/uploads-pvc.yaml`, `uploader.yaml` | Dynamic provisioning from the default class, and the pod that consumes it |
| `manifests/shared-pvc.yaml` | Staged: a ReadWriteMany claim on local-path |
| `manifests/sc-retain.yaml`, `invoices.yaml` | StorageClass `standard-retain` and a claim + pod that use it |
| `manifests/db-headless.yaml`, `db-statefulset.yaml` | Headless Service `db` and a 3-replica Postgres StatefulSet with `volumeClaimTemplates` |
| `manifests/db-oldpath.yaml` | Staged: the StatefulSet with the pre-18 data path |

## Follow along

1. Cluster and namespace. Run everything else from `manifests/`.
   ```bash
   kind create cluster --config kind-cluster.yaml
   cd manifests
   kubectl get nodes
   kubectl create namespace allcsvideos
   kubectl config set-context --current --namespace allcsvideos
   ```

2. **The hook**: a database on `emptyDir`.
   ```bash
   kubectl apply -f db-creds.yaml -f catalog-seed.yaml -f catalog-db.yaml
   kubectl rollout status deployment/catalog-db
   kubectl exec deploy/catalog-db -- psql -U catalog -c 'SELECT id, title FROM courses'
   kubectl exec deploy/catalog-db -- psql -U catalog -c "INSERT INTO courses (title) VALUES ('Kubernetes'), ('GenAI')"
   kubectl exec deploy/catalog-db -- psql -U catalog -c 'SELECT id, title FROM courses'
   kubectl rollout restart deployment/catalog-db
   kubectl rollout status deployment/catalog-db
   kubectl exec deploy/catalog-db -- psql -U catalog -c 'SELECT id, title FROM courses'
   ```
   Five rows after the insert; after the restart, three again (`DSA`, `System Design`, `DevOps`). No error anywhere.

3. The exact `emptyDir` rule: a container crash keeps it, a new pod doesn't.
   ```bash
   kubectl exec deploy/catalog-db -- psql -U catalog -c "INSERT INTO courses (title) VALUES ('Kubernetes')"
   kubectl exec deploy/catalog-db -- gosu postgres pg_ctl stop -m immediate
   sleep 8; kubectl get pods -l app=catalog-db
   kubectl exec deploy/catalog-db -- psql -U catalog -c 'SELECT count(*) FROM courses'
   kubectl delete pod -l app=catalog-db
   kubectl rollout status deployment/catalog-db
   kubectl exec deploy/catalog-db -- psql -U catalog -c 'SELECT count(*) FROM courses'
   ```
   `exit code 137`, `RESTARTS 1`, count `4`; after deleting the pod, count `3`.

4. `hostPath`: data belongs to one node.
   ```bash
   kubectl apply -f hostpath-demo.yaml
   kubectl wait --for=condition=Ready pod/scratch-a
   kubectl exec scratch-a -- cat /scratch/note.txt
   kubectl apply -f hostpath-demo-b.yaml
   kubectl wait --for=condition=Ready pod/scratch-b
   kubectl logs scratch-b
   kubectl get pods -o wide -l '!app'
   docker exec lab-worker ls -l /var/allcsvideos-scratch
   docker exec lab-worker2 ls -l /var/allcsvideos-scratch
   ```
   `scratch-a` prints a date; `scratch-b` on the other worker sees `total 0`. On the nodes: `note.txt` on `lab-worker`, nothing on `lab-worker2`.

5. hostPath is also dangerous, and every pod already has a projected volume.
   ```bash
   kubectl label --dry-run=server --overwrite namespace allcsvideos pod-security.kubernetes.io/enforce=baseline
   kubectl get pod scratch-a -o jsonpath='{.spec.volumes[*].name}'; echo
   kubectl exec scratch-a -- ls /var/run/secrets/kubernetes.io/serviceaccount
   kubectl delete pod scratch-a scratch-b --now
   ```
   The dry run warns `scratch-a (and 1 other pod): hostPath volumes` (the baseline level forbids them). Every pod has `kube-api-access-...` with `ca.crt`, `namespace` and `token`.

6. Static provisioning: the admin writes a PV, the developer a PVC.
   ```bash
   kubectl apply -f pv-static.yaml
   kubectl get pv
   kubectl apply -f pvc-static.yaml
   kubectl get pv,pvc
   kubectl apply -f pvc-too-big.yaml
   kubectl get pvc big-claim
   kubectl events --for pvc/big-claim
   kubectl delete pvc catalog-claim big-claim
   kubectl get pv
   kubectl delete pv catalog-pv
   ```
   `Available`, then both `Bound` - the 1Gi claim gets the whole `2Gi`. The 5Gi claim stays `Pending` with `storageclass.storage.k8s.io "manual" not found`. After deleting the claims, `catalog-pv` is `Released` (Retain keeps it and its data).

7. Dynamic provisioning with kind's default class.
   ```bash
   kubectl get storageclass
   kubectl get pods -n local-path-storage
   kubectl apply -f uploads-pvc.yaml
   kubectl get pvc uploads
   kubectl events --for pvc/uploads
   ```
   You should see:
   ```
   NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
   standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false
   ...
   uploads   Pending   ...   standard
   ...   WaitForFirstConsumer   PersistentVolumeClaim/uploads   waiting for first consumer to be created before binding
   ```
   Not an error: the volume is made only once a pod uses the claim, on that pod's node.

8. Add the consumer and look at what was made.
   ```bash
   kubectl apply -f uploader.yaml
   kubectl wait --for=condition=Ready pod/uploader
   kubectl get pvc uploads
   kubectl get pv
   PV=$(kubectl get pvc uploads -o jsonpath='{.spec.volumeName}')
   kubectl get pv $PV -o yaml
   kubectl logs -n local-path-storage deploy/local-path-provisioner | grep 'uploads'
   kubectl get pod uploader -o wide
   ```
   `Bound` to `pvc-<uid>`, reclaim policy `Delete`. The PV has `provisioned-by: rancher.io/local-path`, a hostPath under `/var/local-path-provisioner`, and nodeAffinity to one worker. Look on **that** node (from `-o wide`):
   ```bash
   docker exec <NODE> ls -l /var/local-path-provisioner
   docker exec <NODE> sh -c 'cat /var/local-path-provisioner/*_uploads/meera.txt'
   ```
   A folder `pvc-..._allcsvideos_uploads` containing `kubernetes-intro.mp4`.

9. Size, expansion and access modes.
   ```bash
   kubectl exec uploader -- df -h /uploads
   kubectl patch pvc uploads -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'
   kubectl apply -f shared-pvc.yaml
   sleep 5; kubectl get pvc shared-uploads
   kubectl get pod shared-user
   kubectl events --for pvc/shared-uploads | grep Failed
   kubectl delete -f shared-pvc.yaml --now
   ```
   `df` shows the node's whole disk, not 1Gi (local-path doesn't enforce size). The patch is `Forbidden` (the class doesn't allow expansion). The RWX claim and its pod stay `Pending`: `NodePath only supports ReadWriteOnce and ReadWriteOncePod`.

10. Reclaim policy `Delete`.
    ```bash
    kubectl delete pod uploader --now
    kubectl delete pvc uploads
    kubectl get pv
    sleep 5; kubectl get pv
    docker exec <NODE> ls -l /var/local-path-provisioner
    kubectl logs -n local-path-storage deploy/local-path-provisioner | grep 'Deleting volume'
    ```
    `Released`, then `No resources found`, and the folder is gone (`total 0`).

11. Reclaim policy `Retain`, with a second class.
    ```bash
    kubectl apply -f sc-retain.yaml
    kubectl apply -f invoices.yaml
    kubectl wait --for=condition=Ready pod/billing
    kubectl get pvc invoices
    kubectl get pod billing -o wide
    kubectl delete pod billing --now
    kubectl delete pvc invoices
    sleep 5; kubectl get pv
    docker exec <BILLING-NODE> sh -c 'ls /var/local-path-provisioner; cat /var/local-path-provisioner/*_invoices/1042.txt'
    ```
    The volume stays `Released` with `Retain`, and `invoice 1042: 499 INR` is still on the node. Even deleting the PV object leaves the folder:
    ```bash
    kubectl delete pv $(kubectl get pv -o jsonpath='{.items[0].metadata.name}')
    docker exec <BILLING-NODE> ls /var/local-path-provisioner
    ```

12. Replace the Deployment with a StatefulSet. Terminal 2 (in `manifests/`): `kubectl get pods -l app=db -w`. Terminal 1:
    ```bash
    kubectl delete deployment catalog-db
    kubectl apply -f db-headless.yaml
    kubectl get svc db
    kubectl apply -f db-statefulset.yaml
    kubectl rollout status statefulset/db
    kubectl get statefulset,pvc
    kubectl get pods -l app=db -o wide
    ```
    `db  ClusterIP  None`. The watch shows `db-0` Pending (volume being made), Running, Ready - and only then `db-1`, then `db-2` (OrderedReady). Three claims `data-db-0/1/2`, all `Bound`.

13. Stable names.
    ```bash
    kubectl run client --image=nicolaka/netshoot:v0.16 --command -- sleep infinity
    kubectl wait --for=condition=Ready pod/client --timeout=180s
    kubectl exec client -- dig +short db-0.db.allcsvideos.svc.cluster.local
    kubectl exec client -- dig +short db-1.db.allcsvideos.svc.cluster.local
    kubectl exec client -- dig +short db.allcsvideos.svc.cluster.local
    kubectl exec db-0 -- hostname -f
    ```
    One IP per pod name, three for `db`, and `db-0.db.allcsvideos.svc.cluster.local`.

14. The hook again, on the StatefulSet (watch running in terminal 2).
    ```bash
    kubectl exec db-0 -- psql -U catalog -c "INSERT INTO courses (title) VALUES ('Kubernetes'), ('GenAI')"
    kubectl exec db-0 -- psql -U catalog -c 'SELECT id, title FROM courses'
    kubectl delete pod db-0
    kubectl wait --for=condition=Ready pod/db-0
    kubectl get pod db-0 -o wide
    kubectl get pod db-0 -o jsonpath='{.spec.volumes[0].persistentVolumeClaim.claimName}'; echo
    kubectl exec db-0 -- psql -U catalog -c 'SELECT id, title FROM courses'
    kubectl exec db-1 -- psql -U catalog -c 'SELECT count(*) FROM courses'
    kubectl exec client -- dig +short db-0.db.allcsvideos.svc.cluster.local
    ```
    A new `db-0`, same node, claim `data-db-0`, and **five rows**. `db-1` has `3`: a StatefulSet doesn't replicate data. DNS for `db-0` follows the new IP.

15. Scale down and up: ordered, and the claims stay.
    ```bash
    kubectl scale statefulset db --replicas=1
    sleep 15; kubectl get pods -l app=db
    kubectl get pvc
    kubectl scale statefulset db --replicas=3
    kubectl rollout status statefulset/db
    kubectl get pvc
    kubectl get statefulset db -o jsonpath='{.spec.podManagementPolicy}{"\n"}{.spec.updateStrategy}{"\n"}{.spec.persistentVolumeClaimRetentionPolicy}{"\n"}'
    ```
    `db-2` terminates first, then `db-1`; all three claims stay `Bound`; scaling up reuses them (Ready in about a second). The policies: `OrderedReady`, `RollingUpdate` with `partition: 0`, and `{"whenDeleted":"Retain","whenScaled":"Retain"}`.

16. Pitfall: the old Postgres data path.
    ```bash
    kubectl apply -f db-oldpath.yaml
    sleep 30; kubectl get pod db-old-0
    kubectl logs db-old-0 | head -12
    kubectl delete statefulset db-old
    kubectl delete pvc data-db-old-0
    ```
    `CrashLoopBackOff`, and `Error: in 18+, these Docker images are configured to store database data in a format which is compatible with "pg_ctlcluster"...`. Mount `/var/lib/postgresql`, not `/var/lib/postgresql/data`.

17. Pitfall: ReadWriteOnce plus node affinity. Use the node `db-0` runs on:
    ```bash
    N=$(kubectl get pod db-0 -o jsonpath='{.spec.nodeName}'); echo $N
    kubectl cordon $N
    kubectl delete pod db-0
    sleep 5; kubectl get pod db-0
    kubectl events --for pod/db-0 | grep FailedScheduling
    kubectl uncordon $N
    kubectl wait --for=condition=Ready pod/db-0
    kubectl get pod db-0 -o wide
    ```
    `Pending`: `didn't match PersistentVolume's node affinity`. After uncordon it's back on the same node.

18. Pitfall: a claim is not a backup.
    ```bash
    kubectl get volumesnapshotclasses
    kubectl exec db-0 -- pg_dump -U catalog -Fc catalog > catalog.dump
    ls -l catalog.dump
    ```
    `the server doesn't have a resource type "volumesnapshotclasses"`; a logical dump always works (about 2.7 KB).

19. Pitfall: deleting a namespace deletes its claims - and `Delete` takes the disks.
    ```bash
    kubectl get pvc
    kubectl delete namespace allcsvideos
    kubectl get pv
    docker exec lab-worker ls /var/local-path-provisioner
    docker exec lab-worker2 ls /var/local-path-provisioner
    ```
    `No resources found`. Only the `..._invoices` folder from the Retain class is left on its node.

## Common mistakes
- **`emptyDir` or `hostPath` for real data.** `emptyDir` dies with the pod; `hostPath` ties data to one node and opens the node to the pod. Use a claim.
- **The Postgres 18 data path.** Mount `/var/lib/postgresql`, not `/var/lib/postgresql/data`.
- **ReadWriteOnce and node affinity.** A local volume can't follow the pod; cloud disks move only inside one zone. "Once" means one node, not one pod.
- **Assuming a claim is a backup.** Snapshots need a CSI driver and the snapshot controller. Take real backups (lesson 5 schedules `pg_dump` as a CronJob).
- **Deleting a namespace.** Every claim goes with it, and `Delete` removes every disk. Use `Retain` for data that matters and restrict who can delete namespaces.
- **Thinking a StatefulSet replicates data.** It gives identity and a disk per pod. Use an operator (CloudNativePG, Zalando) or a managed database for replication, failover and backups.

## Clean up
```bash
rm -f catalog.dump
cd ..
kind delete cluster --name lab
```
(The namespace was deleted in step 19; deleting the cluster also removes the retained `invoices` folder, which lives inside the node container.)

## Next
[M14-L03 · Health and Resources](../m14-l03-health-and-resources/)
