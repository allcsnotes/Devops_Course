#!/usr/bin/env bash
# dr/vault-restore.sh: restore Vault from the newest raft snapshot in the bucket (Vault 2.1.2, integrated storage).
#   1 the new, empty Vault is initialised with a throwaway key (it must be unsealed to accept a restore)
#   2 the snapshot replaces everything: secrets, policies, tokens, auth config AND the old unseal keys
#   3 Vault seals itself; restart it so it reads the restored seal config (drill 1: it still showed 1 share until then)
#   4 unseal with the ORIGINAL key shares (2 of 3, from the break-glass folder)
# Every wait has a time limit and says what it waits for (drill 1: a silent wait hung for 9 minutes).
set -euo pipefail
B=http://10.0.202.6:9000; BG=~/break-glass
st(){ vault status -format=json 2>/dev/null || true; }          # exit code 2 = sealed: not an error here
waitfor(){ local what=$1 limit=$2 t0=$SECONDS; shift 2
  until "$@" >/dev/null 2>&1; do (( SECONDS - t0 > limit )) && { echo "TIMEOUT after ${limit}s: $what"; st; exit 1; }; sleep 1; done
  echo "$(date +%T) vault: $what ($(( SECONDS - t0 )) s)"; }
fresh(){ st | jq -e '.initialized == false'; }
sealed3(){ st | jq -e '.sealed and .n == 3'; }
waitfor "new Vault answers, not initialised" 120 fresh
TMP=$(vault operator init -key-shares=1 -key-threshold=1 -format=json)
vault operator unseal "$(jq -r '.unseal_keys_b64[0]' <<<"$TMP")" >/dev/null
SNAP=$(curl -sf "$B/?prefix=vault/" | awk '{print $4}' | tail -1)
echo "$(date +%T) vault: newest snapshot $SNAP"
curl -sf -o /tmp/vault.snap "$B/$SNAP"
restore(){ VAULT_TOKEN=$(jq -r .root_token <<<"$TMP") vault operator raft snapshot restore -force /tmp/vault.snap; }
waitfor "snapshot restored" 120 restore
rm -f /tmp/vault.snap; unset TMP
docker restart dr-vault >/dev/null
waitfor "sealed again, with the restored 3-share seal" 120 sealed3
for i in 0 1; do vault operator unseal "$(jq -r ".unseal_keys_b64[$i]" $BG/vault-init.json)" >/dev/null; done
st | jq -c '{initialized, sealed, n, t, version}'
