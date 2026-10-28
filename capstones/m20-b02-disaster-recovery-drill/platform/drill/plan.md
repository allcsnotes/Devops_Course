# DR drill plan: lose the whole production environment

- **Goal:** prove we can rebuild allcsvideos production from Git and the off-site bucket, within RTO 15 min and RPO 5 min (lab targets).
- **Staged:** `drill/disaster.sh` deletes the kind cluster, the database and its volume, Vault and its data, monitoring. Lab only.
- **Roles:** Rahul, drill lead (starts the drill, runs the disaster, calls abort, stops the clock) · Asha, recovery (runs the
  runbook, from the checklist only) · Priya, scribe (timeline, every surprise, no blame).
- **Start:** students at steady load for at least 5 minutes, newest base backup and Vault snapshot in the bucket checked.
- **Clock:** starts at DISASTER in the shared drill log `/srv/drill/events.log`, stops when `dr/verify.sh` passes ("restore complete").
- **Abort (stop and protect the backups):** the bucket stops answering or a restore step would write to it · a step reaches
  another team's systems · 45 minutes without a working site (then rebuild by hand, write it all down).
- **Afterwards:** `dr/report.py` for the real RTO and RPO, then the drill report in `docs/`, gaps become tickets, fix, run again.
