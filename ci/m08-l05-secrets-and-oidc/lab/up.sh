#!/usr/bin/env bash
# up.sh - OPTIONAL local OIDC lab for M08-L05, added to the Gitea lab (run ../../m08-l01-what-ci-is/gitea-lab/up.sh
# first). Gitea 28.1.0 issues no OIDC tokens to jobs, so:
#   token-service  a LAB STAND-IN for GitHub's token service (token-service/issuer.py): checks the job's Gitea runtime
#                  token with Gitea, then signs a 5-minute JWT. Port 8080 on the ci-lab network only.
#   vault          HashiCorp Vault 2.1.2 in DEV MODE (in memory, unsealed, lab only) playing "the cloud".
#                  Dev root token: fake-lab-root-token (a FAKE dev-mode value, never a real token).
set -euo pipefail
cd "$(dirname "$0")"
L=(--label course=devops)
docker build -q "${L[@]}" -t lab-token-service token-service >/dev/null
docker run -d "${L[@]}" --name token-service --hostname token-service --network ci-lab --network-alias token-service \
  -e ISSUER=http://token-service:8080 -e GITEA_URL=http://gitea:3000 -e GITEA_TOKEN_FILE=/tmp/gitea-ro-token \
  lab-token-service >/dev/null
# a read-only Gitea token for the token service (generated inside the lab, piped in, never shown)
docker exec -u git gitea gitea admin user generate-access-token --username ci-admin --token-name token-service \
  --scopes read:repository --raw | docker exec -i token-service sh -c 'umask 077; cat > /tmp/gitea-ro-token'
docker run -d "${L[@]}" --name vault --hostname vault --network ci-lab --network-alias vault --cap-add IPC_LOCK \
  -p 127.0.0.1:8200:8200 \
  -e VAULT_DEV_ROOT_TOKEN_ID=fake-lab-root-token -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 hashicorp/vault:2.1.2 >/dev/null
until docker exec -e VAULT_ADDR=http://127.0.0.1:8200 vault vault status >/dev/null 2>&1; do sleep 1; done
docker cp vault/ops-deploy.hcl vault:/tmp/ops-deploy.hcl
docker cp vault/ops-deploy-any.json vault:/tmp/ops-deploy-any.json
echo "oidc lab up. Vault CLI: docker exec -it -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=fake-lab-root-token vault sh"
