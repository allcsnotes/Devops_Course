#!/usr/bin/env bash
# dr/vault-setup.sh: FIRST build only. Initialise Vault (3 key shares, any 2 unseal it), then configure it for allcs.
# The unseal keys and the root token go to the break-glass folder (LAB ONLY: in real life each key share goes to a
# different person, or Vault auto-unseals with a cloud KMS key). They are never in Git and never in the backup bucket.
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077; BG=~/break-glass; mkdir -p $BG && chmod 700 $BG
vault operator init -key-shares=3 -key-threshold=2 -format=json > $BG/vault-init.json
for i in 0 1; do vault operator unseal "$(jq -r ".unseal_keys_b64[$i]" $BG/vault-init.json)" >/dev/null; done
export VAULT_TOKEN=$(jq -r .root_token $BG/vault-init.json)
until vault status >/dev/null 2>&1 && vault secrets list >/dev/null 2>&1; do sleep 1; done
vault secrets enable -path=allcs kv-v2
vault kv put allcs/catalog/db username=allcs password=FAKE-lab-allcs-pass-202 >/dev/null     # FAKE lab password
vault policy write catalog-read - <<'P'
path "allcs/data/catalog/*" { capabilities = ["read"] }
P
vault policy write snapshot - <<'P'
path "sys/storage/raft/snapshot" { capabilities = ["read"] }
P
vault token create -orphan -policy=snapshot -period=768h -display-name=backup-agent -field=token > $BG/vault-snapshot-token
vault auth enable kubernetes
vault write auth/kubernetes/role/catalog bound_service_account_names=catalog-eso bound_service_account_namespaces=allcs \
  audience=vault token_policies=catalog-read token_ttl=10m
dr/vault-k8s-auth.sh
