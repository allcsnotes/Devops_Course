# Optional: the OIDC part of M08-L05 on your laptop (Gitea + token stand-in + Vault)

This replays the video's OIDC demo offline. You don't need it if you follow the GitHub steps in the lesson README.

Gitea 28.1.0 does **not** issue OIDC tokens to jobs, so the video used a small **lab stand-in** token service
(`token-service/issuer.py`) that plays GitHub's part, and **HashiCorp Vault 2.1.2** in dev mode playing the cloud.
Never use either of these outside a lab.

## Steps

1. Start the Gitea lab and push your `allcsvideos-ops` repo to it
   ([`../../m08-l01-what-ci-is/gitea-lab/`](../../m08-l01-what-ci-is/gitea-lab/README.md)). Then:
   ```bash
   bash up.sh
   ```
2. Open a shell with the Vault CLI:
   ```bash
   docker exec -it -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=fake-lab-root-token vault sh
   ```
   Inside it:
   ```bash
   wget -qO- http://token-service:8080/.well-known/openid-configuration
   vault status
   vault auth enable jwt
   vault write auth/jwt/config oidc_discovery_url=http://token-service:8080 bound_issuer=http://token-service:8080
   vault kv put -mount=secret allcsvideos/deploy db_password=demo-db-password-FAKE
   cat /tmp/ops-deploy.hcl
   vault policy write ops-deploy /tmp/ops-deploy.hcl
   vault write auth/jwt/role/ops-deploy role_type=jwt user_claim=sub \
     bound_audiences=vault.lab \
     bound_subject=repo:ci-admin/allcsvideos-ops:ref:refs/heads/main \
     token_policies=ops-deploy token_ttl=5m
   ```
3. In your repo, save [`deploy-gitea.yml`](deploy-gitea.yml) as `.github/workflows/deploy.yml`, commit and
   `git push gitea main`. The run shows the claims (`"sub": "repo:ci-admin/allcsvideos-ops:ref:refs/heads/main"`,
   `exp` 300 s after `iat`), then `{"policies":["default","ops-deploy"],"lease_seconds":300}` and
   `db_password: *** (21 characters)`.
4. Staged: on a branch `priya/try-deploy`, add the branch to the workflow's `branches:` list and push it. The token
   service signs a valid token for `ref:refs/heads/priya/try-deploy`; Vault refuses:
   `error validating token: invalid subject (sub) claim`.
5. Staged, dangerous: in the Vault shell `vault write auth/jwt/role/ops-deploy-any @/tmp/ops-deploy-any.json` (subject
   `repo:ci-admin/allcsvideos-ops:*`), then set `VAULT_ROLE: ops-deploy-any` in the branch's workflow and push: the
   branch now reads the production password. Delete it at once:
   ```bash
   vault delete auth/jwt/role/ops-deploy-any
   vault list auth/jwt/role
   ```
6. The token service's log tells the story (one refusal, then the tokens it issued):
   ```bash
   docker logs token-service
   ```

## Remove it
```bash
bash down.sh
```
