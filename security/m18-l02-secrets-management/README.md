# M18-L02 · Secrets Management
> Video: Module 18, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- Why deleting a leaked secret in a new commit doesn't remove it, and the right order: rotate first, audit, clean, prevent.
- Cleaning a leak out of Git history with `git filter-repo`, and what the server, forks and old clones still hold.
- HashiCorp Vault in real (non-dev) mode: init, unseal, KV v2 versions, policies, AppRole, and dynamic database users that expire.
- AWS Secrets Manager: versions and labels, blocking public policies, deletion windows, rotation, and the CloudTrail audit.
- The External Secrets Operator syncing a Vault secret into a Kubernetes Secret, with no stored password in the cluster.

## Before you start
- Docker Desktop, `bash`, `curl`, `jq`. About 6 GB of free memory for the kind cluster part.
- The lab history from [M18-L01](../m18-l01-shift-left/) (this lab rebuilds it, same commit ids, so you don't need that lab running).
- Free port 3000 (Gitea) and the Docker subnet `10.0.182.0/24` (the lab network uses fixed addresses).
- Pinned versions: `gitea/gitea:28.1.0`, `hashicorp/vault:2.1.2`, `postgres:18.6-alpine3.24`, git-filter-repo 2.47.0,
  gitleaks 8.30.1, kubectl v1.37.1, helm v4.3.1, kind v0.33.0, `kindest/node:v1.36.4` (by digest),
  External Secrets Operator chart 2.13.0.
- For the AWS part: an AWS account or sandbox and AWS CloudShell (or the AWS CLI v2). It creates one secret.
- Every secret in this lab is **fake** or a throwaway lab value. Vault's unseal keys and root token are yours: never
  share real ones.

## Files in this folder
| File | What it is |
|---|---|
| `lab/lab.sh` | `up`, `k8s`, `shell NAME`, `allow` / `reprotect` (force-push rule), `admin-clean`, `delete-fork`, `down` |
| `lab/image/Dockerfile` | The team machine: git, git-filter-repo, gitleaks, the vault CLI, psql, kubectl, helm (pinned) |
| `lab/accounts.txt` | Lab accounts asha, priya, rahul (fake passwords) |
| `stages/` | The repository history the lab rebuilds (M18-L01's, including the staged fake key in commit 2bce599) |
| `vault/vault.hcl` | Vault server config: file storage, sealed at start. **Lab only: TLS off** |
| `vault/catalog-read.hcl` | Policy: read the catalog secrets and database credentials, nothing else |
| `vault/catalog-ro.sql`, `vault/catalog-ro-revoke.sql` | How Vault creates and drops a short-lived read-only Postgres user |
| `db/init.sql` | The lab catalog database and the `vault_admin` account (fake password, rotated by Vault) |
| `k8s/kind-cluster.yaml`, `k8s/tools/Dockerfile` | The kind cluster and the tool box that creates it |
| `k8s/manifests/eso-vault.yaml` | Namespace `allcs`, service account `catalog-eso`, and `vault-reviewer` for TokenReview |
| `k8s/manifests/secretstore.yaml`, `k8s/manifests/externalsecret.yaml` | Where secrets come from (Vault, Kubernetes auth) and what to copy (refresh 15 s) |
| `aws/public-policy.json` | A deliberately public resource policy, to see it blocked |

## Follow along
### Part 1: the leak is still in history
1. Start the lab, then open a shell as rahul.
   ```bash
   cd lab
   ./lab.sh up
   ./lab.sh shell rahul
   ```
2. Today's file is clean; history isn't.
   ```bash
   cd allcsvideos-platform
   git log --oneline -- copilot/app/thumbnails.py
   grep -c AKIA copilot/app/thumbnails.py
   git show 2bce599:copilot/app/thumbnails.py | sed -n 5,7p
   git log --all --oneline -S AKIA2FAKEDEMOKEYZZZZ
   git ls-remote origin
   git ls-remote http://gitea:3000/priya/allcsvideos-platform.git main
   ```
   ```
   0
   AWS_ACCESS_KEY_ID = "AKIA2FAKEDEMOKEYZZZZ"
   5b1c4c7 thumbnails: read the S3 key from the environment
   2bce599 thumbnails: upload course thumbnails to S3
   ...        refs/heads/main
   ...        refs/pull/1/head
   ...        refs/tags/v1.6.0
   ```
   The key was revoked in lesson 1 (step one, always: rotate). Now step three, the clean-up.

3. A mirror clone and a replacements file, then `git filter-repo`.
   ```bash
   cd ~
   printf '%s\n' 'AKIA2FAKEDEMOKEYZZZZ==>***REMOVED-FAKE-KEY***' 'fAkE8dEmO2kEy7oNlY4fOr9tHe3lAb6x8w7v6u5Q==>***REMOVED-FAKE-SECRET***' > leaked.txt
   git clone -q --mirror http://gitea:3000/allcsvideos/allcsvideos-platform.git
   cd allcsvideos-platform.git
   git filter-repo --version
   git filter-repo --sensitive-data-removal --replace-text ../leaked.txt
   ```
   ```
   Parsed 12 commits
   You rewrote 10 (of 12) commits.
   NOTE: First Changed Commit(s) is/are:
     2bce599f29fb83dc2007f0f0d0f9423f0dfed0d8
   ```
4. Check before pushing, then push.
   ```bash
   git log --all --oneline -S AKIA2FAKEDEMOKEYZZZZ | wc -l
   git show v1.6.0:copilot/app/thumbnails.py | sed -n 5,7p
   git for-each-ref --format='%(objectname:short) %(refname)'
   git push --force --mirror origin
   ```
   `0`, placeholders in v1.6.0, and the push is rejected: `Branch main is protected from force push`.
   Asha (the admin) allows it for rahul only, for this one push (laptop, in `lab/`):
   ```bash
   ./lab.sh allow
   ```
   ```
   {"enable_force_push":true,"force_push_allowlist_usernames":["rahul"]}
   ```
   Back in rahul's shell:
   ```bash
   git push --force --mirror origin
   ```
   ```
    + c0dbfd4...1551ae4 main -> main (forced update)
    + 91fc82a...a767544 v1.6.0 -> v1.6.0 (forced update)
    ! [remote rejected] refs/pull/1/head -> refs/pull/1/head (hook declined)
   ```
   Then turn protection back on (laptop): `./lab.sh reprotect`.

5. What's left. In rahul's shell:
   ```bash
   git ls-remote origin
   curl -s -o /dev/null -w '%{http_code}\n' http://gitea:3000/allcsvideos/allcsvideos-platform/commit/2bce599f29fb83dc2007f0f0d0f9423f0dfed0d8
   git ls-remote http://gitea:3000/priya/allcsvideos-platform.git main
   ```
   The pull request ref still points at the old commits, the old commit page answers `200`, and Priya's fork still has
   the old main. An old clone is worse (`./lab.sh shell priya`):
   ```bash
   cd allcsvideos-platform
   git pull
   git log --all --oneline -S AKIA2FAKEDEMOKEYZZZZ
   ```
   `fatal: Need to specify how to reconcile divergent branches.` and both commits with the key are still there.

6. The clean-up needs other people. The server admin (laptop):
   ```bash
   ./lab.sh admin-clean
   ./lab.sh delete-fork
   ```
   ```
   git@gitea:...$ git update-ref -d refs/pull/1/head
   git@gitea:...$ git reflog expire --expire=now --all && git gc -q --prune=now
   git@gitea:...$ git cat-file -t 2bce599f29fb83dc2007f0f0d0f9423f0dfed0d8
   fatal: git cat-file: could not get object info
   delete fork: HTTP 204
   ```
   The old commit page now returns `404`. On GitHub you contact GitHub Support for pull request refs and cached views,
   and ask fork owners yourself. Then everyone re-clones (priya):
   ```bash
   cd ~ && rm -rf allcsvideos-platform
   git clone -q http://gitea:3000/allcsvideos/allcsvideos-platform.git && cd allcsvideos-platform
   git log --all --oneline -S AKIA2FAKEDEMOKEYZZZZ | wc -l
   git rm -q .gitleaksignore
   git commit -qm 'gitleaks: history purged, drop the 1.6.0 ignore entry'
   gitleaks git --redact --no-banner .
   git push -q
   ```
   `0`, and `INF no leaks found` without the exception from lesson 1.

### Part 2: Vault
7. Open a shell as asha (`./lab.sh shell asha`). A real server starts uninitialised and sealed (exit code 2).
   ```bash
   vault version
   vault status
   vault operator init -key-shares=3 -key-threshold=2
   ```
   Vault prints three unseal keys and a root token **once**. Keep them in a scratch note for this lab only.
   ```bash
   vault operator unseal        # paste key 1: Unseal Progress 1/2
   vault operator unseal        # paste another key: Sealed false
   vault login -no-print        # paste the root token (setup only)
   vault token lookup | grep -E '^(display_name|policies)'
   ```
8. KV version 2, and versions as your undo.
   ```bash
   vault secrets enable -path=allcs kv-v2
   vault kv put allcs/catalog/db username=catalog_app password=FAKE-vault-pass-001
   vault kv put allcs/catalog/db username=catalog_app password=FAKE-vault-pass-002
   vault kv get allcs/catalog/db
   vault kv get -version=1 -field=password allcs/catalog/db; echo
   ```
9. A policy and an AppRole login for the catalog service.
   ```bash
   cat catalog-read.hcl
   vault policy write catalog-read catalog-read.hcl
   vault auth enable approle
   vault write auth/approle/role/catalog token_policies=catalog-read token_ttl=15m secret_id_ttl=24h
   ROLE_ID=$(vault read -field=role_id auth/approle/role/catalog/role-id)
   SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/catalog/secret-id)
   export VAULT_TOKEN=$(vault write -field=token auth/approle/login role_id=$ROLE_ID secret_id=$SECRET_ID)
   vault token lookup | grep -E '^(display_name|policies|ttl)'
   vault kv get -field=password allcs/catalog/db; echo
   vault kv put allcs/catalog/db password=changed-by-the-app
   ```
   ```
   policies            [catalog-read default]
   ttl                 14m58s
   FAKE-vault-pass-002
   Code: 403. Errors:
           * permission denied
   ```
10. Dynamic database credentials. Connect Vault to Postgres, then rotate the admin password so only Vault knows it.
    ```bash
    unset VAULT_TOKEN
    vault secrets enable database
    vault write database/config/catalog plugin_name=postgresql-database-plugin allowed_roles=catalog-ro connection_url='postgresql://{{username}}:{{password}}@db:5432/catalog' username=vault_admin password=FAKE-lab-vault-admin-123
    vault write -force database/rotate-root/catalog
    PGPASSWORD=FAKE-lab-vault-admin-123 psql -w -h db -U vault_admin -d catalog -c 'select 1'
    cat catalog-ro.sql catalog-ro-revoke.sql
    vault write database/roles/catalog-ro db_name=catalog creation_statements=@catalog-ro.sql revocation_statements=@catalog-ro-revoke.sql default_ttl=2m max_ttl=10m
    ```
    The old admin password now fails: `password authentication failed for user "vault_admin"`.
    ```bash
    export VAULT_TOKEN=$(vault write -field=token auth/approle/login role_id=$ROLE_ID secret_id=$(vault write -f -field=secret_id auth/approle/role/catalog/secret-id))
    vault read -format=json database/creds/catalog-ro > creds.json
    jq '{lease_id, lease_duration, username: .data.username}' creds.json
    U=$(jq -r .data.username creds.json); P=$(jq -r .data.password creds.json)
    psql -w "postgresql://$U:$P@db/catalog" -c 'select title, price_inr from courses'
    psql -w "postgresql://$U:$P@db/catalog" -c 'delete from courses'
    PGPASSWORD=FAKE-lab-postgres-123 psql -h db -U postgres -d catalog -c "select rolname, rolvaliduntil from pg_roles where rolname like 'v-%'"
    ```
    A brand-new user with a 120-second lease; reads work, `delete` gets `permission denied`.
11. Revoke it, or let it expire.
    ```bash
    unset VAULT_TOKEN
    vault lease revoke -sync $(jq -r .lease_id creds.json)
    psql -w "postgresql://$U:$P@db/catalog" -c 'select 1'
    PGPASSWORD=FAKE-lab-postgres-123 psql -h db -U postgres -d catalog -Atc "select count(*) from pg_roles where rolname like 'v-%'"
    vault read -format=json database/creds/catalog-ro | jq -r '.data.username, .lease_duration'; date +%T
    sleep 125; date +%T
    PGPASSWORD=FAKE-lab-postgres-123 psql -h db -U postgres -d catalog -Atc "select count(*) from pg_roles where rolname like 'v-%'"
    ```
    The login fails after revoke, and `0` dynamic users are left both times.

### Part 3: AWS Secrets Manager (costs money: see the box)
> **Cost:** USD 0.40 per secret per month plus USD 0.05 per 10,000 API calls (AWS pricing page, 21 October 2026).
> The steps end by force-deleting the secret. Use only fake values.

12. In AWS CloudShell:
    ```bash
    aws secretsmanager create-secret --name allcs/prod/db --description "FAKE lab secret: allcsvideos catalog database" --secret-string '{"username":"catalog_app","password":"FAKE-demo-password-123","host":"allcs-db.example.internal","port":5432}' --tags Key=Project,Value=allcsvideos Key=Env,Value=prod
    aws secretsmanager describe-secret --secret-id allcs/prod/db
    aws secretsmanager get-secret-value --secret-id allcs/prod/db --query SecretString --output text | jq .
    aws kms describe-key --key-id alias/aws/secretsmanager --query "KeyMetadata.[KeyId,KeyManager,KeySpec,KeyState]"
    aws secretsmanager put-secret-value --secret-id allcs/prod/db --secret-string '{"username":"catalog_app","password":"FAKE-demo-password-456","host":"allcs-db.example.internal","port":5432}'
    aws secretsmanager list-secret-version-ids --secret-id allcs/prod/db
    aws secretsmanager get-secret-value --secret-id allcs/prod/db --version-stage AWSPREVIOUS --query SecretString --output text | jq -r .password
    ```
    ```
    "ARN": "arn:aws:secretsmanager:us-east-1:123456789012:secret:allcs/prod/db-AbCdEf",
    "VersionStages": ["AWSPREVIOUS"] ... ["AWSCURRENT"]
    FAKE-demo-password-123
    ```
13. Rotation needs a Lambda function, and a public policy is refused. Upload `aws/public-policy.json` to CloudShell first.
    ```bash
    aws secretsmanager rotate-secret --secret-id allcs/prod/db --rotation-rules AutomaticallyAfterDays=30
    aws secretsmanager validate-resource-policy --secret-id allcs/prod/db --resource-policy file://public-policy.json
    aws secretsmanager put-resource-policy --secret-id allcs/prod/db --resource-policy file://public-policy.json --block-public-policy
    ```
    ```
    An error occurred (InvalidRequestException) ... No Lambda rotation function ARN is associated with this secret.
    "CheckName": "BlockPublicPolicyCheck"
    An error occurred (PublicPolicyException) ... You can not attach a resource policy that grants Public access to your secret.
    ```
    The four rotation steps a Lambda runs: `createSecret` (AWSPENDING), `setSecret`, `testSecret`, `finishSecret`
    (AWSCURRENT moves, the old one becomes AWSPREVIOUS). For RDS, the master password can be managed and rotated for you.
14. The audit trail, then delete.
    ```bash
    aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue=allcs/prod/db --max-results 20 --query 'Events[].[EventTime,EventName,Username]' --output table
    aws secretsmanager delete-secret --secret-id allcs/prod/db --recovery-window-in-days 7
    aws secretsmanager get-secret-value --secret-id allcs/prod/db
    aws secretsmanager delete-secret --secret-id allcs/prod/db --force-delete-without-recovery
    ```
    The video's sandbox listed 14 events in 16 seconds, from `CreateSecret` to the blocked `PutResourcePolicy`
    (recorded in full). After the first delete, reads fail: `marked for deletion`. (In the video's sandbox
    `restore-secret` was denied; in your own account you can restore within the window.)

### Part 4: External Secrets Operator
15. Create the cluster (laptop, a few minutes), then in asha's shell install ESO.
    ```bash
    ./lab.sh k8s
    ```
    ```bash
    kubectl get nodes
    helm repo add external-secrets https://charts.external-secrets.io
    helm install external-secrets external-secrets/external-secrets --version 2.13.0 -n external-secrets --create-namespace --wait
    kubectl get pods -n external-secrets
    ```
    Three pods: the controller, the webhook and the cert controller.
16. Kubernetes auth in Vault (as root, so `unset VAULT_TOKEN` first if you set it).
    ```bash
    kubectl apply -f eso-vault.yaml
    kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > k8s-ca.crt
    vault auth enable kubernetes
    vault write auth/kubernetes/config kubernetes_host=https://10.0.182.30:6443 kubernetes_ca_cert=@k8s-ca.crt token_reviewer_jwt="$(kubectl get secret vault-reviewer-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)"
    vault write auth/kubernetes/role/catalog bound_service_account_names=catalog-eso bound_service_account_namespaces=allcs audience=vault token_policies=catalog-read token_ttl=10m
    ```
17. The SecretStore and the ExternalSecret.
    ```bash
    kubectl apply -f secretstore.yaml -f externalsecret.yaml
    kubectl wait externalsecret/catalog-db -n allcs --for=condition=Ready --timeout=120s
    kubectl get secretstore,externalsecret -n allcs
    kubectl get secret catalog-db -n allcs -o jsonpath='{.data.password}'; echo
    kubectl get secret catalog-db -n allcs -o jsonpath='{.data.password}' | base64 -d; echo
    ```
    `Valid`, `SecretSynced`, then `RkFLRS12YXVsdC1wYXNzLTAwMg==` which decodes to `FAKE-vault-pass-002`: base64 is encoding,
    not encryption.
18. Change it in Vault and watch the cluster follow, within one refresh interval.
    ```bash
    vault kv put -mount=allcs catalog/db username=catalog_app password=FAKE-vault-pass-003 | grep -E '^version'; date +%T
    for i in $(seq 8); do echo "$(date +%T) $(kubectl get secret catalog-db -n allcs -o jsonpath='{.data.password}' | base64 -d)"; sleep 3; done
    ```
    ```
    00:20:43 FAKE-vault-pass-002
    00:20:46 FAKE-vault-pass-003
    ```
    Environment variables read a Secret only when the container starts: mount it as a file, or roll the pods.

## Common mistakes
- **Secrets in environment variables, printed in logs.** Never log the environment.
- **Long-lived static keys.** Prefer short-lived credentials: OIDC, IRSA, dynamic database users.
- **Base64 confusion.** A Kubernetes Secret is encoded, not encrypted. Turn on encryption at rest and limit reads with RBAC.
- **Rewriting history without rotating.** The key is still in every old clone and fork. Rotate first, always.
- **A dev-mode Vault, or a root token left lying around.** Run real mode with TLS, and revoke the root token after setup.

## Clean up
```bash
./lab.sh down
```
On AWS, make sure `aws secretsmanager list-secrets` no longer shows `allcs/prod/db`.

## Next
[M18-L03 · Supply-Chain Security](../m18-l03-supply-chain-security/)
