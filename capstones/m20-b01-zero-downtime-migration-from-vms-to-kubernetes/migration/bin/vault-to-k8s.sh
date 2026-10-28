#!/bin/bash
# vault-to-k8s.sh: one source of truth for secrets. Reads the VM fleet's Ansible vault and writes the same values into
# Kubernetes Secrets in namespace allcs (values never printed). In production this is External Secrets + Vault (M18-L02).
set -euo pipefail
cd ~/migration/ansible
get(){ ansible-vault view group_vars/web/vault.yml | ~/.venvs/ansible/bin/python -c "import sys,yaml; print(yaml.safe_load(sys.stdin)['$1'])"; }
kubectl create namespace allcs --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n allcs create secret generic allcs-api-db --from-literal=password="$(get vault_db_password)" \
  --dry-run=client -o yaml | kubectl apply --server-side -f -
kubectl -n allcs create secret generic allcs-api-session --from-literal=key="$(get vault_session_secret)" \
  --dry-run=client -o yaml | kubectl apply --server-side -f -
