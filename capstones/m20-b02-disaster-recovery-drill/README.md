# M20-B02 · Disaster-Recovery Drill
> Video: Module 20, Build 2. Watch it first, then follow along here.

Delete the whole allcsvideos production environment (cluster, database, Vault, monitoring) and rebuild it from Git
and an off-site backup bucket, against a time target. Drill 1 misses both targets; you fix four gaps and drill 2 makes it.

## What you'll learn
- Set the RTO, the RPO and what "restored" means **before** the drill (lab targets: RTO 15 min, RPO 5 min).
- Keep three things apart: code in Git, data in an off-site bucket, keys in a break-glass folder.
- PostgreSQL point-in-time recovery from base backups + archived WAL, and Vault restore from a raft snapshot.
- Run the runbook as a script, measure RTO and RPO from timestamps, and write a blameless drill report.
- Why `archive_timeout`, restored state that trusts a deleted cluster, and silent waits break a recovery.
- What changes at real scale: pilot light, warm standby, RDS PITR, AWS Backup Vault Lock, Velero, KMS auto-unseal.

## Before you start
- Docker Desktop with about 4 GB of free memory. Run `bash lab/down.sh` of any other lab first (this one uses ports 3000, 3001, 5001, 9000, 9090).
- Internet access for the first run (images, the Argo CD manifest, the External Secrets Helm chart).
- Everything else is in the ops box that `lab/up.sh` builds. Pinned versions: Terraform 1.16.6 with the
  `kreuzwerker/docker` provider 4.6.0, Vault 2.1.2, PostgreSQL 18.6, kind v0.33.0 (`kindest/node:v1.36.4`),
  kubectl v1.36.4, Argo CD v3.5.6 (core), External Secrets 2.13.0, Prometheus v3.15.0, Grafana 13.2.4, Gitea 28.1.0,
  registry 3.1.2, `nginxinc/nginx-unprivileged:1.29.8-alpine`, `python:3.13.16-slim`.
- Builds on [M20-B01](../m20-b01-zero-downtime-migration-from-vms-to-kubernetes/) (allcsvideos on Kubernetes with Git as
  the source of truth) and on [M17-L04](../../observability/m17-l04-chaos-engineering-and-disaster-recovery/) (backups and restore drills).

## Files in this folder
| File | What it is |
|------|------------|
| `lab/up.sh` | Builds the survivors (Git server, bucket, registry, ops laptop), pushes the platform repo as "runbook v1" |
| `lab/students.sh` | `start` / `stop` the simulated students (10 req/s, 1 in 5 enrolls; writes `acks.csv`) |
| `lab/down.sh` | Removes everything the lab created |
| `lab/images/` | Images: `postgres` (+ WAL archive/restore scripts, `dr-entrypoint.sh`), `backup-agent`, `bucket` (S3 stand-in), `api` (+ `loadgen.py`), `ops` |
| `platform/infra/` | Terraform: database, Vault, backup agent, Prometheus, Grafana (Docker provider; state in the bucket) |
| `platform/bootstrap/` | `cluster.sh`, kind config, Argo CD core kustomization, the root app |
| `platform/apps/`, `platform/charts/allcs/` | What Argo CD installs: External Secrets, platform objects, the allcs Helm chart |
| `platform/dr/` | The runbook: `restore.sh`, `vault-restore.sh`, `wait.sh`, `verify.sh`, `report.py`, `restore-test.sh`, `vault-setup.sh`, `vault-k8s-auth.sh`, `mark.sh`, `CHECKLIST.md` |
| `platform/drill/` | `plan.md` (the drill plan) and `disaster.sh` (the staged disaster) |
| `platform/docs/drill-report.md` | The blameless drill report from the video |
| `drill1/` | The four files as they were in drill 1 (runbook v1, `archive_timeout = "0"`) |

`platform/` is the **fixed** version (after drill 1). `lab/up.sh` pushes `platform/` with `drill1/` on top, so your
Git server starts at runbook v1, the version that fails, just like in the video. The ops box sees this lesson folder
read-only at `~/course`, so you can copy the fixes in later.

## Follow along
0. Build the survivors (on your laptop, from this folder) and open two shells: Asha (recovery) and Rahul (drill lead).
   ```bash
   cd capstones/m20-b02-disaster-recovery-drill
   bash lab/up.sh
   docker exec -it -u asha -w /home/asha/platform dr-ops bash      # terminal 1: Asha
   docker exec -it -u rahul -w /home/rahul dr-ops bash             # terminal 2: Rahul
   ```

### Step 1: build production the first time, from Git only (Asha)
1. Look at the repo, then give Terraform its two secrets from the break-glass folder (the snapshot token does not exist yet).
   ```bash
   git log --oneline
   ls infra infra/files bootstrap apps/* charts/allcs dr drill
   export TF_VAR_db_admin_password=$(cat ~/break-glass/db-admin-password) TF_VAR_vault_snapshot_token=not-set-yet
   ```
2. Terraform: the Docker provider, and state in the bucket (http backend).
   ```bash
   terraform -chdir=infra init -input=false -no-color | grep -E 'backend|Installing|Installed|successfully'
   time terraform -chdir=infra apply -input=false -auto-approve -no-color | grep -E 'Creation complete|Apply complete'
   ```
   `Apply complete! Resources: 14 added` (4 volumes, 5 images, 5 containers). The database seeds itself with 40
   courses and 300,000 fake enrollments.
3. The cluster: kind, join the lab network, Argo CD, its Git token, the root app.
   ```bash
   time bootstrap/cluster.sh
   ```
   ```
   02:52:27 cluster: 1/5 kind create cluster dr (kindest/node v1.36.4)
   ...
   02:53:18 cluster: 5/5 the root app: from here on, Git is the source of truth
   application.argoproj.io/root created
   ```
4. Vault: initialise (3 key shares, 2 to unseal) and configure. The keys go to the break-glass folder.
   ```bash
   dr/vault-setup.sh
   ls -l ~/break-glass
   ```
5. Give the backup agent its snapshot token: Terraform replaces it.
   ```bash
   export TF_VAR_vault_snapshot_token=$(cat ~/break-glass/vault-snapshot-token)
   terraform -chdir=infra apply -input=false -auto-approve -no-color | grep -E 'must be replaced|Plan:|Apply complete'
   ```
6. Start the students (laptop terminal), then check that Git has taken over.
   ```bash
   bash lab/students.sh start
   ```
   ```bash
   kubectl get applications -n argocd
   kubectl get pods -n allcs
   kubectl get externalsecret -n allcs
   tail -3 ~/students/acks.csv
   ```
   Four apps `Synced Healthy`, two `api` pods and one `web` pod `Running`, `catalog-db  SecretSynced  True`.

### Step 2: backups, configured and verified once
7. What is in the bucket, and what the database archives.
   ```bash
   curl -s 'http://10.0.202.6:9000/?prefix=base/'
   curl -s 'http://10.0.202.6:9000/?prefix=wal/' | tail -4
   curl -s 'http://10.0.202.6:9000/?prefix=vault/' | tail -3
   docker logs --tail 4 dr-backup-agent
   export PGPASSWORD=$(cat ~/break-glass/db-admin-password)
   psql -h 10.0.202.10 -U postgres -d catalog -c 'show archive_mode' -c 'show archive_command' -c 'show archive_timeout'
   psql -h 10.0.202.10 -U postgres -d catalog -c 'select archived_count, last_archived_wal, last_archived_time, failed_count from pg_stat_archiver'
   ```
   `archive_timeout` is `0`, the default. Remember that line.
8. The restore test: a throwaway PostgreSQL restores the newest base backup + all WAL, never writing to the bucket.
   ```bash
   time dr/restore-test.sh
   ```
   ```
   restored: 300000 enrollments, newest row 2026-10-19 21:32:26
   live:     300000 enrollments up to that moment
   RESTORE TEST PASSED in 4 s
   ```
   Look at that "newest row" date. It is correct, and stale.

### Steps 3 and 4: the runbook and the drill plan
9. Read `dr/restore.sh` (five steps, each written to the shared drill log `/srv/drill/events.log`), `dr/verify.sh`
   (what "restored" means, as code), `dr/CHECKLIST.md` and `drill/plan.md` (roles, clock, abort rules).

### Drill 1
10. Let the students run for about 10 minutes. Rahul checks the bucket, then runs the staged disaster.
    ```bash
    curl -s 'http://10.0.202.6:9000/?prefix=base/' | tail -1
    curl -s 'http://10.0.202.6:9000/?prefix=vault/' | tail -1
    date +%T
    platform/drill/disaster.sh
    ```
    ```
    03:04:24 DISASTER (staged): deleting production
      removed container dr-db
      ...
      removed volume dr-pgdata
    03:04:28 production is gone. Left: dr-bucket dr-git dr-ops dr-registry dr-students
    ```
    (kind may complain it cannot edit Asha's kubeconfig from Rahul's shell; the node is deleted anyway.)
11. Asha: a fresh clone, and the runbook.
    ```bash
    cd ~ && git clone -q http://10.0.202.5:3000/allcsvideos/platform.git drill1 && cd drill1
    time dr/restore.sh
    ```
    Step 1 finishes in about 15 s (`Apply complete! Resources: 9 added`). Step 2 prints nothing, ever. After a while press Ctrl+C.
12. Diagnose: a sealed Vault exits with code 2, and the wait loop runs under `pipefail`.
    ```bash
    dr/mark.sh 'step 2 hung: no output for 9 minutes, interrupted'
    vault status; echo "exit code $?"
    grep -n 'until vault status' dr/vault-restore.sh
    ```
13. Fix it by hand in the clone and run step 2 again.
    ```bash
    sed -i 's/until vault status -format=json\( 2>\/dev\/null\)\? |/until { vault status -format=json 2>\/dev\/null || true; } |/' dr/vault-restore.sh
    git diff --stat; grep -n 'until' dr/vault-restore.sh | cut -c1-110
    dr/mark.sh 'step 2 again: vault-restore.sh fixed by hand (vault status exits 2 when sealed)'
    time dr/vault-restore.sh
    ```
    The snapshot restores, but unsealing fails: `invalid key size 33`. Vault still shows the throwaway 1-share seal.
14. Restart Vault so it reads the restored seal, then unseal with two of the original shares.
    ```bash
    docker restart dr-vault
    sleep 3; vault status | grep -E '^(Initialized|Sealed|Total Shares|Threshold)'
    for i in 0 1; do vault operator unseal "$(jq -r ".unseal_keys_b64[$i]" ~/break-glass/vault-init.json)" | grep -E '^(Sealed|Unseal Progress)'; done
    VAULT_TOKEN=$(jq -r .root_token ~/break-glass/vault-init.json) vault kv get -mount=allcs -field=username catalog/db
    ```
    `Total Shares 3`, `Threshold 2`, then `Sealed false`, and `allcs`.
15. Continue the runbook by hand: cluster, then wait.
    ```bash
    dr/mark.sh 'step 3 cluster: kind + Argo CD from bootstrap/, then Git takes over'
    bootstrap/cluster.sh
    dr/mark.sh 'step 4 wait: database recovery, Argo CD sync, secrets, pods'
    dr/wait.sh
    ```
    `TIMEOUT after 300s: ExternalSecret catalog-db`, and the SecretStore says `InvalidProviderConfig`.
16. Why: Vault answers 403, because the snapshot brought back its trust in the **deleted** cluster's CA.
    ```bash
    kubectl describe secretstore vault -n allcs | tail -6 | cut -c1-118
    export VAULT_TOKEN=$(jq -r .root_token ~/break-glass/vault-init.json)
    vault read -field=kubernetes_ca_cert auth/kubernetes/config | head -3
    kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d | head -3
    ```
    The two certificates differ.
17. Re-point Vault at the new cluster, wait, and verify. External Secrets had backed off, so it needs one more forced sync.
    ```bash
    dr/mark.sh 'fix: Vault still trusts the deleted cluster, re-run vault-k8s-auth.sh'
    dr/vault-k8s-auth.sh
    kubectl annotate externalsecret catalog-db -n allcs force-sync=$(date +%s) --overwrite
    dr/wait.sh
    kubectl get secretstore vault -n allcs
    kubectl annotate externalsecret catalog-db -n allcs force-sync=$(date +%s) --overwrite
    dr/wait.sh
    dr/mark.sh 'step 5 verify'
    dr/verify.sh && dr/mark.sh 'restore complete'
    ```
    Six `PASS` lines, then `== restore complete`.
18. The report, from timestamps only.
    ```bash
    dr/report.py 'drill 1'
    ```
    ```
    newest confirmed row restored  02:56:50
    RPO (data lost)                7 min 34 s, 908 confirmed enrollments gone
    students enroll again          03:29:01  RTO 24 min 36 s
    verify passed, clock stopped   03:29:05  RTO 24 min 40 s
    ```
    Both targets missed. Your numbers will differ; the shape will not.

### Fix the four gaps (Asha, in `~/platform`)
19. Copy in the fixed files, one commit per gap, like the video.
    ```bash
    cd ~/platform
    cp ~/course/platform/dr/vault-restore.sh dr/
    git commit -qam 'dr: vault-restore v2: sealed is not an error, restart after restore, every wait has a time limit (drill 1)'
    cp ~/course/platform/dr/restore.sh ~/course/platform/dr/wait.sh dr/
    git commit -qam 'dr: re-point Vault Kubernetes auth at the new cluster, force one ESO sync when the store is ready (drill 1)'
    cp ~/course/platform/infra/variables.tf infra/
    git commit -qam 'infra: archive_timeout 60 s, so a WAL file leaves the server at least every minute (drill 1 RPO)'
    cp ~/course/platform/dr/restore-test.sh dr/
    git commit -qam 'dr: the restore test fails when the newest restored row is older than the RPO target'
    git push -q
    git log --oneline -4
    ```
20. The stricter restore test now fails against today's backups, as it should.
    ```bash
    dr/restore-test.sh
    ```
    ```
    newest restored row is 2050 s old (RPO target 300 s)
    RESTORE TEST FAILED: the backups are older than the RPO target
    ```
21. Apply the new `archive_timeout` (the database container is replaced), wait a few minutes, test again.
    ```bash
    export TF_VAR_db_admin_password=$(cat ~/break-glass/db-admin-password) TF_VAR_vault_snapshot_token=$(cat ~/break-glass/vault-snapshot-token)
    terraform -chdir=infra apply -input=false -auto-approve -no-color | grep -E 'must be replaced|archive_timeout|Plan:|Apply complete'
    curl -s 'http://10.0.202.6:9000/?prefix=wal/' | tail -3
    dr/restore-test.sh
    ```
    `"archive_timeout=0" -> "archive_timeout=60"`, a WAL file a minute in the bucket, and
    `newest restored row is 15 s old` ... `RESTORE TEST PASSED`.

### Drill 2
22. Rahul: update his clone, check the bucket, delete production again.
    ```bash
    cd ~/platform && git pull -q && cd ~
    curl -s 'http://10.0.202.6:9000/?prefix=wal/' | tail -1
    curl -s 'http://10.0.202.6:9000/?prefix=vault/' | tail -1
    date +%T
    platform/drill/disaster.sh
    ```
23. Asha: a fresh clone of the fixed main branch, the whole runbook, the report.
    ```bash
    cd ~ && git clone -q http://10.0.202.5:3000/allcsvideos/platform.git drill2 && cd drill2
    time dr/restore.sh
    dr/report.py 'drill 2'
    ```
    ```
    RPO (data lost)                0 min 22 s, 44 confirmed enrollments gone
    students enroll again          03:48:57  RTO 6 min 20 s
    verify passed, clock stopped   03:48:59  RTO 6 min 22 s
    ```
    Both inside the targets. Not zero: the last WAL file was still on the server when it died.
24. Open Grafana at http://localhost:3000: the dashboards are back from Git, the history before the disaster is gone.
    Read the finished report in `platform/docs/drill-report.md`, then write your own with your numbers.

## Common mistakes
- **Targets set after the drill.** Agree RTO, RPO and "restored means" first, in writing.
- **A runbook step that only ever ran by hand.** Silent waits with no time limit hang forever; every wait needs a limit and must say what it waits for.
- **Restored state that points at the deleted environment.** Vault's Kubernetes auth came back trusting the old cluster's CA.
- **`archive_timeout = 0`.** WAL only leaves the server when 16 MB fill up; at low traffic that is hours. Alert on the age of the newest WAL in the bucket.
- **A restore test that only checks "it restored".** Also check how old the newest restored row is.
- **Keys next to the backups.** Unseal keys and admin passwords go in a third place, never in Git or the bucket.
- **Rebuild-from-nothing at cloud scale.** An EKS control plane alone took 10 min 4 s in module 15; a 15-minute RTO on AWS needs pilot light or warm standby.

## Clean up
On your laptop:
```bash
bash lab/students.sh stop
bash lab/down.sh
rm -rf ~/dr-lab-students        # the students' CSV files, if you no longer want them
```

## Next
[M20-B03 · Troubleshooting Labs](../m20-b03-troubleshooting-labs/)
