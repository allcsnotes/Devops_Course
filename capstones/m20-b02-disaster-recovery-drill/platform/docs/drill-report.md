# DR drill report: lose the whole production environment (2026-10-22, lab)

Blameless. Staged disaster (drill/disaster.sh). Targets set before the drill: RTO 15 min, RPO 5 min (lab targets).
Measured with dr/report.py from the drill log, the students' acks.csv and the restored database. The laptop was shared
with other labs (load average about 9 to 10 during both drills), so cluster and image-pull times are slower than usual.

| | Drill 1 (runbook v1) | Drill 2 (runbook v2) | Target |
|---|---|---|---|
| RTO (verify passed) | 24 min 40 s | 6 min 22 s | 15 min |
| Students enroll again | 24 min 36 s | 6 min 20 s | |
| RPO | 7 min 34 s | 22 s | 5 min |
| Confirmed enrollments lost | 908 | 44 | |

## Timeline, drill 1 (03:04:24 disaster)
- +0:06 terraform apply: 9 resources, the database restored itself from the bucket
- +0:21 vault-restore.sh started, printed nothing, and never ended
- +10:01 noticed and interrupted. Cause: `vault status` exits 2 when Vault is sealed, so the wait loop under `pipefail` never succeeded
- +10:14 fixed by hand; the restore worked but Vault sealed itself and still showed the throwaway 1-share seal: restarted, then unsealed with 2 of the 3 original shares
- +11:14 cluster.sh: kind + Argo CD, Git took over (apps synced 84 s later)
- +18:39 wait.sh timed out: ESO could not log in to Vault (403 permission denied). The restored Vault still trusted the DELETED cluster (its CA and reviewer token came back with the snapshot)
- +19:05 vault-k8s-auth.sh re-pointed Vault at the new cluster; ESO still needed a second forced sync after its store turned valid
- +24:40 verify passed

## What went well
- Everything was rebuilt from Git and the bucket only: Terraform state, base backup, WAL, Vault snapshot, dashboards.
- The break-glass folder had every key we needed. Nobody needed anything from the deleted environment.

## Gaps found, and the fixes (all merged before drill 2)
1. A runbook step that had never run as a script: silent wait, no time limit. Fix: vault-restore v2 (sealed is not an error, restart after restore, every wait has a limit and says what it waits for).
2. Restored state that points at the deleted environment: Vault's Kubernetes auth. Fix: restore.sh step 3b, run vault-k8s-auth.sh against the new cluster; wait.sh forces one ESO sync when the store is ready.
3. RPO 7.5 min: archive_timeout was 0 (the default), so WAL only left the server when a 16 MB file filled or a base backup ran. Fix: archive_timeout 60 s.
4. The restore test passed while its newest restored row was two days old. Fix: it now fails when the newest restored row is older than the RPO target.

## Still open
- Right after a restore, the first WAL file left the new primary only after about 5 minutes, then every minute: RPO is weaker in that window. Ticket: take a base backup and check archiving as part of verify.
- Argo CD sync took 250 s in drill 2, mostly image pulls on a loaded laptop. Ticket: a pull-through cache / pre-pulled images in the recovery region.
- kind delete warned it could not edit Asha's kubeconfig from Rahul's shell (lab wart, the node was deleted).
- Next drill: in 3 months, with a different person running the runbook.
