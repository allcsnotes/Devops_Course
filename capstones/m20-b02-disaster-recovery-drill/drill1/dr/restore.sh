#!/usr/bin/env bash
# dr/restore.sh: the DR runbook as a script. Rebuild allcsvideos production from Git (this repo) and the off-site bucket.
# Run from a fresh clone on the ops laptop. Needs: the break-glass folder (keys), the bucket, the Git server, the registry.
set -euo pipefail
cd "$(dirname "$0")/.."
mark(){ dr/mark.sh "$@"; }
export TF_VAR_db_admin_password=$(cat ~/break-glass/db-admin-password)
export TF_VAR_vault_snapshot_token=$(cat ~/break-glass/vault-snapshot-token)

mark "step 1 infrastructure: terraform apply, the database restores itself from the bucket"
terraform -chdir=infra init -input=false >/dev/null
terraform -chdir=infra apply -input=false -auto-approve -no-color -var db_source=pitr | grep -E '^Plan:|^Apply complete'

mark "step 2 vault: restore the newest snapshot, unseal with the original key shares"
dr/vault-restore.sh

mark "step 3 cluster: kind + Argo CD from bootstrap/, then Git takes over"
bootstrap/cluster.sh

mark "step 4 wait: database recovery, Argo CD sync, secrets, pods"
dr/wait.sh

mark "step 5 verify"
dr/verify.sh
mark "restore complete"
