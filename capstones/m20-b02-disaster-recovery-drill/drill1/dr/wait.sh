#!/usr/bin/env bash
# dr/wait.sh: wait (with time limits) until the database has recovered, Argo CD has synced, ESO has the secret and the
# API pods are ready. Each wait prints what it is waiting for, and fails loudly with the reason when time runs out.
set -uo pipefail
waitfor(){ local what=$1 limit=$2 test=$3 why=$4 t0=$SECONDS
  until eval "$test" >/dev/null 2>&1; do
    (( SECONDS - t0 > limit )) && { echo "$(date +%T) wait: TIMEOUT after ${limit}s: $what"; eval "$why"; exit 1; }
    sleep 5; done
  echo "$(date +%T) wait: $what ($(( SECONDS - t0 )) s)"; }
export PGPASSWORD=$(cat ~/break-glass/db-admin-password)
waitfor "database recovered and writable" 600 \
  '[[ $(psql -h 10.0.202.10 -U postgres -d catalog -Atc "select pg_is_in_recovery()") == f ]]' \
  'docker logs --tail 5 dr-db'
waitfor "Argo CD: external-secrets, platform, allcs synced" 900 \
  '[[ $(kubectl get applications -n argocd -o json | jq "[.items[] | select(.status.sync.status==\"Synced\")] | length") -ge 4 ]]' \
  'kubectl get applications -n argocd'
waitfor "ExternalSecret catalog-db: secret copied from Vault" 300 \
  'kubectl get externalsecret catalog-db -n allcs -o jsonpath="{.status.conditions[0].status}" | grep -qx True' \
  'kubectl get externalsecret,secretstore -n allcs; kubectl get secretstore vault -n allcs -o jsonpath="{.status.conditions[0].message}"; echo'
waitfor "API pods ready" 300 \
  'kubectl rollout status deployment/api -n allcs --timeout=5s' \
  'kubectl get pods -n allcs'
