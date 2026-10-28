#!/usr/bin/env bash
# dr/vault-restore.sh: restore Vault from the newest raft snapshot in the bucket (Vault 2.1.2, integrated storage).
#   1 the new, empty Vault is initialised with a throwaway key (it must be unsealed to accept a restore)
#   2 the snapshot replaces everything: secrets, policies, tokens, auth config AND the old unseal keys
#   3 so Vault is sealed again, and opens only with the ORIGINAL key shares (2 of 3, from the break-glass folder)
set -euo pipefail
B=http://10.0.202.6:9000; BG=~/break-glass
until vault status -format=json 2>/dev/null | jq -e '.initialized == false' >/dev/null; do sleep 1; done
TMP=$(vault operator init -key-shares=1 -key-threshold=1 -format=json)
vault operator unseal "$(jq -r '.unseal_keys_b64[0]' <<<"$TMP")" >/dev/null
SNAP=$(curl -sf "$B/?prefix=vault/" | awk '{print $4}' | tail -1)
echo "newest snapshot: $SNAP"
curl -sf -o /tmp/vault.snap "$B/$SNAP"
until VAULT_TOKEN=$(jq -r .root_token <<<"$TMP") vault operator raft snapshot restore -force /tmp/vault.snap; do sleep 2; done
rm -f /tmp/vault.snap; unset TMP
until vault status -format=json | jq -e '.sealed' >/dev/null; do sleep 1; done      # the restored keyring seals Vault
for i in 0 1; do vault operator unseal "$(jq -r ".unseal_keys_b64[$i]" $BG/vault-init.json)" >/dev/null; done
vault status -format=json | jq -c '{initialized, sealed, version}'
