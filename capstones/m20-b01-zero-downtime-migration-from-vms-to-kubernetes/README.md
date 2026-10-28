# M20-B01 · Zero-Downtime Migration from VMs to Kubernetes
> Video: Module 20, Build 1. Watch it first, then follow along here.

allcsvideos runs on two VMs (module 12). You move it to Kubernetes (module 15) while k6 "students" keep sending
40 requests per second, and nobody notices: traffic moves at the edge in steps of 5, 25, 50 and 100 %, and an SLO
gate decides after every step whether to go on or go back.

## What you'll learn
- The strangler-fig pattern: both worlds behind one edge load balancer, traffic moved in slices with nginx `split_clients`.
- An SLO gate built from what users see (k6 counters in Prometheus), and an instant rollback: Kubernetes to 0 %.
- Why two pools on one database need a connection budget, and why secrets must come from one source.
- Rollout safety in Kubernetes: `maxSurge 1 / maxUnavailable 0`, a readiness probe, a `preStop` sleep, a PodDisruptionBudget.
- How to test the gate itself, and why a gate that cannot see errors is worse than no gate.
- What changes at real scale: DNS weights, ALB weighted target groups, expand-and-contract schema changes.

## Before you start
- Docker Desktop with about 4 GB of free memory (the lab runs ~12 containers plus a kind node; Grafana adds ~600 MB).
- Everything else (Ansible, kubectl, Helm, kind, psql, k6) runs in containers that `lab/up.sh` builds. Pinned versions:
  kind v0.33.0, node image `kindest/node:v1.36.4`, kubectl v1.36.4, Helm v4.3.1, ansible-core 2.21.5, Argo CD v3.5.6
  (core install), nginx 1.29.8, PostgreSQL 18.6, Prometheus v3.15.0, Gitea 28.1.0, k6 2.3.0, Grafana 13.2.4,
  `python:3.13.16-slim` for the app image.
- Helpful background: [`ansible/m12-b01-configure-a-vm-fleet-with-ansible`](../../ansible/m12-b01-configure-a-vm-fleet-with-ansible/) (the VM fleet),
  [`k8s/m15-b01-deploy-allcsvideos-to-eks-with-helm-and-argo-cd`](../../k8s/m15-b01-deploy-allcsvideos-to-eks-with-helm-and-argo-cd/) (Helm + Argo CD),
  [`capstones/m20-l01-designing-a-production-delivery-platform`](../m20-l01-designing-a-production-delivery-platform/) (the ADR that asked for this move).
- On Linux, the Docker socket may not be writable for user `asha` inside the ops box. If `docker` fails there, run
  `docker exec -u root mig-ops chmod 666 /var/run/docker.sock` (lab only).

## Files in this folder
| File | What it is |
|------|------------|
| `lab/up.sh` | Builds the lab: network, Postgres, two "VMs", edge, Prometheus, Gitea, ops box, kind cluster, Argo CD |
| `lab/grafana.sh` | Optional: Grafana with the migration dashboard on http://localhost:3000 |
| `lab/reset.sh` | Puts the lab back to the "before" state for another rehearsal |
| `lab/down.sh` | Removes everything the lab created |
| `lab/images/vm/`, `lab/images/ops/` | The "VM" image (Ubuntu 24.04 + systemd + SSH) and the ops box image |
| `lab/setup-node.sh` | Makes each VM bare like a fresh cloud server (user `asha`, her SSH key) |
| `lab/db/init.sql`, `lab/prometheus/`, `lab/grafana/` | Database schema (fake data), Prometheus scrape config, dashboard |
| `migration/app/` | The catalog API (`api.py`), its `requirements.txt`, and the new `Dockerfile` |
| `migration/ansible/` | The VM fleet playbook (`site.yml`), `decommission.yml`, the `api` role, inventory, vars |
| `migration/ansible/group_vars/web/vault.plain.yml` | FAKE secrets; `up.sh` encrypts them into `vault.yml` |
| `migration/deploy/` | The deploy repo: Helm chart `charts/allcs-api` and the Argo CD `apps/` (project + application) |
| `migration/edge/` | nginx edge config and `split/weights.conf` (the traffic split) |
| `migration/k6/students.js` | The students: 70 % course list, 20 % who-am-I, 10 % progress writes |
| `migration/kind/kind-cluster.yaml`, `migration/argocd/` | One-node kind cluster; Argo CD core install (kustomize) |
| `migration/bin/` | `load.sh`, `gate.sh`, `shift.sh`, `migrate.sh`, `drain.sh`, `parity.sh`, `vault-to-k8s.sh`, `report.py`, `rollback-check.py`, `edge` |

## Follow along
All lesson commands run inside the ops box, as `asha`, in `~/migration` (your copy at `~/migration-lab`).

0. Build the lab (from this folder, on your laptop), then open a shell on the ops box.
   ```bash
   cd capstones/m20-b01-zero-downtime-migration-from-vms-to-kubernetes
   bash lab/up.sh
   docker exec -it -w /home/asha/migration mig-ops bash
   ```
   Keep a second terminal on the ops box for k6 (`docker exec -it -w /home/asha/migration mig-ops bash`).

### Step 1: a baseline on the VMs
1. Re-run the module 12 playbook: nothing has drifted.
   ```bash
   cd ansible
   ansible-playbook site.yml
   cd ..
   ```
   You should see `web-01 : ok=10 changed=0` and `web-02 : ok=10 changed=0`.
2. One request through the edge, twice, and the split file.
   ```bash
   curl -s -D - -o /dev/null 10.0.201.5/api/courses | grep -E '^X-'
   curl -s -D - -o /dev/null 10.0.201.5/api/courses | grep -E '^X-'
   cat edge/split/weights.conf
   ```
   ```
   X-Served-By: web-01
   X-App-Version: 2.4.0
   X-Edge-Pool: vm_pool
   ```
   The second answer comes from `web-02`. The split sends `*` to `vm_pool`.
3. Start the students in the second terminal (40 requests/s for 2 minutes), then, while it runs, gate and drain in the first.
   ```bash
   load.sh base 40 2m
   ```
   ```bash
   gate.sh 60
   drain.sh
   ```
   ```
   SLO gate, last 60 s     requests   errors  over 250 ms
     Kubernetes pool              0        0            0   no traffic
     all students              2400        0            0   ok
   PASS (errors <= 0.1 %, slow <= 1 %)
   ```
4. When k6 finishes, the exact numbers from the per-request log.
   ```bash
   report.py base
   ```
   ```
   run base: 4,800 requests in 1m 59s (40.0 per second)
   pool    requests  failed   p95 ms   p99 ms
   vm         4,800       0      2.8      5.2
   ```
   Optional: `bash lab/grafana.sh` on your laptop and open http://localhost:3000.

### Step 2: containerise and package
5. Build the image from the same `api.py` the VMs run, and load it into the kind node. The video also had a second
   tag, `2.4.1`, for the rollout tests later; build it too (a label is enough to make it a different image).
   ```bash
   docker build -q -t allcs-api:2.4.0 app
   docker build -q --label version=2.4.1 -t allcs-api:2.4.1 app
   docker image ls allcs-api
   kind load docker-image --name mig allcs-api:2.4.0 allcs-api:2.4.1
   ```
   You should see a content size of about `47.8MB`.
6. Lint and render the chart with production values.
   ```bash
   cd deploy
   helm lint charts/allcs-api -f charts/allcs-api/values-prod.yaml
   helm template allcs-api charts/allcs-api -f charts/allcs-api/values-prod.yaml | grep -E '^kind|replicas|seconds|path: /'
   ```
   `1 chart(s) linted, 0 chart(s) failed`, `replicas: 3`, both probes, and `sleep: {seconds: 5}` for preStop.

### Step 3: deploy with GitOps, test without users
7. Secrets from the Ansible vault into Kubernetes, then push the deploy repo and create the Argo CD app.
   ```bash
   vault-to-k8s.sh
   git init -q && git add . && git commit -qm 'allcs-api chart 0.3.0, Argo CD project and app'
   git remote add origin http://10.0.201.40:3000/allcsvideos/allcsvideos-deploy.git
   git push -q -u origin main
   kubectl apply -f apps/
   ```
8. The first real problem.
   ```bash
   kubectl -n argocd get application allcs-api
   kubectl -n allcs get pods
   kubectl -n allcs logs deploy/allcs-api --previous
   ```
   ```
   allcs-api-6bb48f48cb-vbl72   0/1     CrashLoopBackOff   2 (3s ago)   18s
   cannot open database connection 8 of 10: remaining connection slots are reserved for roles with the SUPERUSER attribute
   ```
9. Count the connections.
   ```bash
   export PGHOST=10.0.201.20 PGUSER=postgres PGDATABASE=catalog
   psql -c "SELECT client_addr, count(*) FROM pg_stat_activity WHERE usename = 'allcs' GROUP BY 1"
   psql -c 'SHOW max_connections' -c 'SHOW superuser_reserved_connections'
   ```
   Each VM holds 10; max is 30 with 3 reserved, so 27 for the app and only 7 left for the pods.
   Budget: (2 VMs + 3 pods + 1 surge pod) x 4 = 24 of 27.
10. Set 4 on the VMs. Edit `ansible/group_vars/web/vars.yml`:
    ```yaml
    db_pool: 4                        # connection budget: (2 VMs + 3 pods + 1 surge pod) x 4 = 24 of 27
    ```
    ```bash
    cd ../ansible
    grep db_pool group_vars/web/vars.yml
    ansible-playbook site.yml | grep -E 'PLAY|changed:|web-0'
    cd ../deploy
    ```
    One server at a time (`serial: 1`): `changed=2` on each.
11. Set 4 on the pods. Add to `charts/allcs-api/values-prod.yaml`, under `replicas: 3`:
    ```yaml
    db:
      pool: 4                             # connection budget: (2 VMs + 3 pods + 1 surge pod) x 4 = 24 of 27
    ```
    ```bash
    git diff
    git commit -qam 'connection budget: 4 per instance' && git push -q
    ```
12. Watch the rollout. It can stall: an old pod restarted just as the VMs freed connections and grabbed 10.
    ```bash
    kubectl -n allcs get pods
    psql -c "SELECT client_addr, count(*) FROM pg_stat_activity WHERE usename = 'allcs' GROUP BY 1"
    kubectl -n allcs get pdb
    ```
    Nothing serves from Kubernetes yet, so delete the Deployment and let Argo CD recreate it from Git.
    ```bash
    kubectl -n allcs delete deployment allcs-api
    kubectl -n allcs get pods
    psql -c "SELECT client_addr, count(*) FROM pg_stat_activity WHERE usename = 'allcs' GROUP BY 1"
    kubectl -n argocd get application allcs-api
    ```
    Three pods `Running`; 4 + 4 from the VMs, 12 from `10.0.201.60`; `Synced  Healthy`.
13. A synthetic test straight at the Kubernetes Service (skipping the edge), then delete its tagged test writes.
    ```bash
    cd ..
    BASE=http://10.0.201.60:30080 load.sh synthetic 10 30s
    report.py synthetic
    psql -c "DELETE FROM progress WHERE run = 'synthetic'"
    ```
    `301 requests ... 0 failed`, `DELETE 28` (your counts may differ slightly).

### Step 4: shift at the edge
14. Try one step by hand, and check the config the way `shift.sh` does.
    ```bash
    shift.sh 5
    cat edge/split/weights.conf
    edge nginx -t
    ```
    ```
    split_clients "${request_id}" $pool {
        5%   k8s_pool;
        *     vm_pool;
    }
    ```
    Put it back with `shift.sh 0`. `migrate.sh` walks 5, 25, 50, 100 with a 60-second soak and a gate after each.

### Step 5: drain and decommission
`drain.sh` (in-flight requests + open TCP connections per VM) and `ansible/decommission.yml` (stops the API one
server at a time; the servers stay) are used in the real run below.

### Step 6: rehearse the rollback under load
15. Second terminal: `load.sh rehearsal 40 4m`. First terminal, after about a minute:
    ```bash
    shift.sh 5
    gate.sh 60
    shift.sh 50
    gate.sh 30
    shift.sh 0
    ```
    Both gates pass (`Kubernetes pool 103 0 0 ok`). When k6 ends:
    ```bash
    rollback-check.py rehearsal
    report.py rehearsal
    ```
    ```
    rollback to 0 %:                  02:55:04.017
    last answer from Kubernetes:      02:55:04.029 (+12 ms)
    requests sent to Kubernetes after: 0
    failed requests within 10 s:      0
    ```

### Run it
16. Back up first, and prove the backup restores.
    ```bash
    pg_dump -Fc -f backups/catalog-before-cutover.dump
    ls -lh backups/
    pg_restore -l backups/catalog-before-cutover.dump | grep 'TABLE DATA'
    createdb catalog_check && pg_restore -d catalog_check backups/catalog-before-cutover.dump
    psql -d catalog_check -Atc 'SELECT count(*) FROM progress'
    psql -Atc 'SELECT count(*) FROM progress'
    dropdb catalog_check
    ```
    The two counts must match (1951 in the video).
17. Second terminal: `load.sh migration 40 9m`. First terminal, after one minute of baseline:
    ```bash
    migrate.sh
    ```
    ```
    02:58:52 edge: 5 % to Kubernetes, 95 % to the VMs
      Kubernetes pool            107        0            0   ok
    ...
    03:01:52 edge: 100 % to Kubernetes, 0 % to the VMs
      Kubernetes pool           2400        0            0   ok
    03:02:53 migration complete: 100 % of students on Kubernetes
    ```
18. Drain and decommission.
    ```bash
    drain.sh
    cd ansible
    ansible-playbook decommission.yml
    cd ..
    drain.sh
    ssh -q asha@10.0.201.11 sudo journalctl -u allcs-api -n 6 --no-pager -o cat
    ```
    Before: `in flight: 0  open connections: 1` (that one is Prometheus scraping). After: `- (API stopped)`, and the
    journal shows `SIGTERM: draining web-01, 0 requests in flight` then `stopped cleanly: web-01`.
19. When k6 ends, check users and data.
    ```bash
    report.py migration
    psql -Atc "SELECT count(*) FROM progress WHERE run = 'migration'"
    psql -c "SELECT client_addr, count(*) FROM pg_stat_activity WHERE usename = 'allcs' GROUP BY 1"
    ```
    ```
    run migration: 21,601 requests in 8m 59s (40.0 per second)
    pool    requests  failed   p95 ms   p99 ms
    vm         7,713       0      3.3      6.5
    k8s       13,888       0      4.8     21.7
    all       21,601       0      4.2     13.7
    progress writes acknowledged (201): 2,119
    ```
    The row count must equal the acknowledged writes (2119 = 2,119).

### Break it on purpose
Put the VMs back first: on your laptop run `bash lab/reset.sh`, then repeat step 7 (secrets, `git init`, push, `kubectl apply -f apps/`).

20. **Mistake one: environment parity.** Delete the two `session:` lines from `deploy/charts/allcs-api/values-prod.yaml`.
    ```bash
    cd deploy
    git diff
    git commit -qam 'staged mistake: values-prod without the session secret' && git push -q
    cd ..
    ```
    A synthetic test still passes (`BASE=http://10.0.201.60:30080 load.sh synthetic2 10 20s`, `report.py synthetic2`,
    then `psql -c "DELETE FROM progress WHERE run = 'synthetic2'"`): it logs in on the pods themselves.
    Now the real thing: second terminal `load.sh b1 40 3m`, first terminal `migrate.sh`.
    ```
      Kubernetes pool            125       15            0   BREACH
    03:11:50 gate failed at 5 %: rolling back
    ```
    ```bash
    report.py b1
    parity.sh
    ```
    `k8s  401  me  15`, and `SESSION_SECRET ... DIFFERENT`. Fix it with Git:
    ```bash
    cd deploy
    git revert --no-edit HEAD | head -1
    git push -q
    cd ..
    parity.sh
    STEPS=5 migrate.sh
    shift.sh 0
    ```
    All five variables say `yes`, and the 5 % step passes with 0 errors.
21. **Mistake two: a rollout without readiness probe and preStop.** In `deploy/charts/allcs-api/templates/deployment.yaml`
    delete the 5 `readinessProbe` lines and the 3 `lifecycle`/`preStop` lines (8 lines).
    ```bash
    cd deploy
    git diff --stat
    git commit -qam 'staged mistake: no readiness probe, no preStop hook' && git push -q
    cd ..
    ```
    Second terminal: `load.sh b2 40 150s`. First terminal: move everyone to Kubernetes, then roll out a new tag through
    Git (change `tag: "2.4.0"` to `"2.4.1"` in `charts/allcs-api/values.yaml`):
    ```bash
    shift.sh 100
    cd deploy
    git commit -qam 'api 2.4.1' && git push -q
    kubectl -n argocd annotate application allcs-api argocd.argoproj.io/refresh=normal --overwrite
    sleep 5; kubectl -n allcs rollout status deploy/allcs-api --timeout=300s
    cd ..
    gate.sh 60
    shift.sh 0
    report.py b2
    ```
    The gate says `FAIL` (about 4 errors, Prometheus extrapolates); `report.py` shows the exact 502s from the edge.
    Fix it, then repeat the rollout under load (`load.sh b2fix 40 150s`, commit `'api 2.4.0'` going back to `2.4.0`):
    ```bash
    cd deploy
    git log --oneline -4
    git revert --no-edit <hash of the 'staged mistake: no readiness probe' commit> | head -1
    git push -q
    kubectl -n argocd annotate application allcs-api argocd.argoproj.io/refresh=normal --overwrite
    sleep 5; kubectl -n allcs rollout status deploy/allcs-api --timeout=300s | tail -1
    kubectl -n allcs get deploy allcs-api -o yaml | grep -E -A1 'readinessProbe:|preStop:'
    cd ..
    ```
    The video's fixed run: `6,001 requests, k8s 2,417, failed 0`, and the gate passes.
22. **Test the gate itself.** In the video the first gate run *passed* while 6 requests failed: Prometheus `increase()`
    cannot see the first value of a counter series that appears mid-window. `students.js` already has the fix (every
    counter is created at 0 at the start, the `primed` block). Comment that block out and repeat mistake two to see
    the gate miss the errors.

## Common mistakes
- **No connection budget.** Two pools on one database: count every instance that can run at once, including the
  surge pod, and remember old and new settings overlap during a rollout. At real scale put PgBouncer or RDS Proxy in between.
- **Environment drift.** A secret that exists on the VMs but not in the pods logs students out (401). One source of
  truth for secrets, and run `parity.sh` (hashes only, never values) before the first shift.
- **No readiness probe / no preStop.** Old pods stop listening while kube-proxy still sends them traffic; new pods get
  traffic before they are ready: 502s at the edge.
- **An untested gate.** A gate that cannot see errors is worse than none. Test it with a failure you know is there.
- **Moving data and traffic at once.** The database does not move today. Schema changes use expand, migrate, contract.
- **DNS as the edge.** Weighted records are only as fast as the TTL; lower it days before.

## Clean up
On your laptop:
```bash
bash lab/down.sh
rm -rf ~/migration-lab        # your working copy, if you no longer want it
```

## Next
[M20-B02 · Disaster-Recovery Drill](../m20-b02-disaster-recovery-drill/)
