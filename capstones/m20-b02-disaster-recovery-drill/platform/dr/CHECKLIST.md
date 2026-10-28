# allcsvideos production: disaster-recovery checklist

Targets (lab): RTO 15 min (students can browse and enroll), RPO 5 min (confirmed enrollments lost).

## Before you start
- [ ] Incident declared, a drill lead / incident commander named, a scribe writing the timeline
- [ ] The off-site bucket answers: `curl -s http://10.0.202.6:9000/?prefix=base/ | tail -1` (it is the ONLY copy: never write to it by hand)
- [ ] The break-glass folder is on this laptop: Vault key shares, snapshot token, database admin password, Git read token
- [ ] A fresh clone of the platform repo (Git is the source of truth, not anyone's old checkout)

## Restore (dr/restore.sh runs these in order)
1. Infrastructure: `terraform apply -var db_source=pitr` (the database restores the newest base backup + every archived WAL file)
2. Vault: `dr/vault-restore.sh` (new Vault, restore the newest snapshot, unseal with 2 of the 3 ORIGINAL key shares)
3. Cluster: `bootstrap/cluster.sh` (kind, Argo CD, the root app; Argo CD installs the rest from Git)
4. Wait: database writable, apps synced, ExternalSecret ready, API pods ready
5. Verify: `dr/verify.sh` (browse, a real enrollment, secrets, dashboards, WAL archiving)

## Done means
- [ ] Students can browse and enroll (first confirmed enrollment after the disaster)
- [ ] Data verified: row count and newest row printed, RPO measured with `dr/report.py`
- [ ] Secrets back: ExternalSecret synced from the restored Vault
- [ ] Dashboards back: the production board in Grafana (metrics history before the disaster is gone: not backed up)
- [ ] A new base backup taken on the new database (the backup agent does it at start)

## Not backed up, on purpose
- Prometheus metrics history and Grafana's own database: rebuilt empty, dashboards come from Git
- The kind cluster itself (etcd): everything in it is rebuilt from Git by Argo CD
- Pods, caches, sessions: stateless, recreated
