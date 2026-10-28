# M11-L05 · Environments and Pipelines
> Video: Module 11, Lesson 5. Watch it first, then follow along here.

## What you'll learn
- Why every environment needs **its own state** (blast radius, different permissions, different speed of change)
- Three approaches: **CLI workspaces**, **one folder per environment** (recommended for most teams), or a tool on top (Terragrunt, HCP Terraform)
- The real limits of CLI workspaces: same backend, same credentials, invisible selection
- A pipeline where **nobody applies from a laptop**: `fmt`, `validate` and `plan` on every pull request, the plan posted as a comment, the **saved plan** applied after merge (staging automatically, production after a person approves)
- Split credentials: read-only for plans, write per environment; on AWS use OIDC and read-only roles
- tflint, Checkov, `terraform test`, and why a **stale saved plan** is refused

## Before you start
- **Part A (AWS):** the `~/tf/net` project from [M11-L04](../m11-l04-modules/) with `module.staging_net` applied, in AWS CloudShell (us-east-1, Terraform v1.16.6).
- **Part B (local pipeline lab):** Docker Desktop (about 3 GB of images) and a free port 3000. Everything runs in Docker with **no cloud**: Gitea 28.1.0 with Gitea Actions (same workflow syntax as GitHub Actions), a Gitea runner, PostgreSQL as the state backend, and a "team machine" with Terraform 1.16.6 and tflint 0.64.0. The module uses `terraform_data` stand-ins instead of real VPCs. This is the same Gitea setup as Modules 8 and 9.

> **Cost.** Part A only *plans* in a new workspace and then **destroys** the lesson 4 network, so it costs nothing.
> Part B is local and free. Clean up: `bash lab/down.sh`.

## Files in this folder
| File | What it is |
|---|---|
| `allcsvideos-infra/` | the repository: `envs/staging`, `envs/prod` (own backend + inputs each), `modules/network` (stand-in network module), `.gitignore` |
| `allcsvideos-infra/.gitea/workflows/terraform.yml` | the pipeline: `fmt` -> `plan` (matrix staging/prod, plan posted on PRs, saved as artifact on main) -> `apply-staging` |
| `infra-production/.gitea/workflows/apply-prod.yml` | production gate in a releasers-only repo: started by hand with a run number, applies exactly that run's saved prod plan |
| `lab/up.sh`, `lab/down.sh` | start / remove the whole local lab |
| `lab/state-admin.sql` | state database: a schema per environment, roles `tf_plan` (read-only), `tf_staging`, `tf_prod` (fake passwords) |
| `lab/image/Dockerfile`, `lab/runner/config.yaml` | the team machine image and the runner config |
| `lab/accounts.txt` | the lab's fake accounts (asha, priya, rahul) |

## Follow along

### Part A - CLI workspaces (AWS CloudShell)
1. List workspaces and create `prod`:
   ```bash
   cd ~/tf/net
   terraform workspace list
   terraform workspace new prod
   ```
   ```
   * default
   Created and switched to workspace "prod"!
   You're now on a new, empty workspace. Workspaces isolate their state, ...
   ```

2. Plan in the new workspace (**plan only, do not apply**):
   ```bash
   terraform workspace show; terraform plan -no-color -target=module.staging_net | grep -E "name|Name|Plan:" | head -8
   ```
   `prod`, then names like `"Name" = "allcs-prod-public-0"`: `terraform.workspace` flowed into the module's `name` input. With the S3 backend, non-default workspaces are stored under `env:/<workspace>/<key>` in the same bucket.

3. Delete the empty workspace, then destroy the lesson 4 network (the end of the AWS part):
   ```bash
   terraform workspace select default; terraform workspace delete prod
   terraform destroy -no-color -auto-approve -target=module.staging_net | tail -4
   ```
   `Deleted workspace "prod"!` and `Destroy complete! Resources: 3 destroyed.`

### Part B - one folder per environment, with a pipeline (local)
4. Start the lab (from this folder on your laptop):
   ```bash
   bash lab/up.sh
   ```
   It ends with `lab up: open http://localhost:3000`. Log in there with the accounts in `lab/accounts.txt` when a step uses the web UI. Links inside Gitea may show `http://gitea:3000/...`; replace `gitea` with `localhost` in your browser.

5. **Asha** sets up the repository. Open a shell as her on the team machine:
   ```bash
   docker exec -it -u asha -w /home/asha tflab-team bash
   ```
   then, inside it:
   ```bash
   git clone -q http://gitea:3000/allcsvideos/allcsvideos-infra.git && cd allcsvideos-infra
   cp -r /tmp/infra-src/. . && for e in staging prod; do terraform -chdir=envs/$e init -backend=false >/dev/null; done
   tree -a -I '.git|.terraform' --noreport
   diff -r -x .terraform envs/staging envs/prod
   cat modules/network/main.tf
   cat envs/prod/main.tf
   ```
   The `init -backend=false` creates each environment's `.terraform.lock.hcl`. The `diff` shows the whole difference between the environments - two files:
   ```
   envs/staging/backend.tf  schema_name = "staging"   |  envs/prod/backend.tf  schema_name = "prod"
   envs/staging/terraform.tfvars env = "staging", cidr = "10.1.0.0/16"  |  prod: env = "prod", cidr = "10.0.0.0/16"
   ```

6. Push to `main` (run 1: `fmt`, two plans, `apply-staging`):
   ```bash
   git add .
   git commit -qm 'infra: one folder per environment, pipeline plans and applies'
   git push -q origin HEAD:main
   ```
   Watch it under **allcsvideos-infra -> Actions** in the browser. All green; staging now has its 4 stand-in resources.

7. **Rahul** approves the first production apply: log in as `rahul`, open **infra-production -> Actions -> apply-prod -> Run workflow**, enter run number `1`. Its log ends with `Apply complete! Resources: 4 added`.

8. Asha protects `main`: no direct pushes, one approval, the three checks must pass (still in Asha's shell):
   ```bash
   curl -s -X POST -H "Authorization: token $(cat ~/.gitea-token)" -H 'Content-Type: application/json' \
     http://gitea:3000/api/v1/repos/allcsvideos/allcsvideos-infra/branch_protections \
     -d '{"rule_name":"main","enable_push":false,"required_approvals":1,"enable_status_check":true,"status_check_contexts":["terraform / fmt (pull_request)","terraform / plan (staging) (pull_request)","terraform / plan (prod) (pull_request)"],"block_on_rejected_reviews":true,"dismiss_stale_approvals":true}' | jq -c '{rule_name, enable_push, required_approvals}'
   exit
   ```

9. **Priya** adds a third zone to prod, on a branch, typed without spaces (a staged, common mistake):
   ```bash
   docker exec -it -u priya -w /home/priya tflab-team bash
   ```
   ```bash
   git clone -q http://gitea:3000/allcsvideos/allcsvideos-infra.git && cd allcsvideos-infra
   git switch -q -c priya/prod-third-zone
   sed -i 's/^zones = .*/zones = ["us-east-1a","us-east-1b","us-east-1c"]/' envs/prod/terraform.tfvars
   git diff
   git commit -qam 'prod: a third availability zone'
   git push -q -u origin priya/prod-third-zone
   curl -s -X POST -H "Authorization: token $(cat ~/.gitea-token)" -H 'Content-Type: application/json' \
     http://gitea:3000/api/v1/repos/allcsvideos/allcsvideos-infra/pulls \
     -d '{"head":"priya/prod-third-zone","base":"main","title":"prod: a third availability zone","body":"Adds us-east-1c to prod (10.0.103.0/24). Staging stays on two zones."}' | jq -r .html_url
   ```
   Run 2: the **fmt** job fails and its `-diff` shows the fix; the plan jobs never start:
   ```
   -zones = ["us-east-1a","us-east-1b","us-east-1c"]
   +zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
   ##[error]Process completed with exit code 3.
   ```

10. Fix it and push again:
    ```bash
    terraform fmt -recursive
    git diff
    git commit -qam 'prod: terraform fmt'
    git push -q
    ```
    `fmt` prints the file it fixed (`envs/prod/terraform.tfvars`). Run 3 is green, and two comments appear on the pull request:
    ```
    ### terraform plan: staging
    No changes. Your infrastructure matches the configuration.

    ### terraform plan: prod
    # module.network.terraform_data.subnet["us-east-1c"] will be created
        + cidr = "10.0.103.0/24"
        + name = "allcs-prod-public-us-east-1c"
    Plan: 1 to add, 0 to change, 0 to destroy.
    ```
    Staging is untouched: folder isolation, proven by the plan.

11. **Rahul** reviews in the browser (as `rahul`): code (one line) and plan (1 to add, nothing destroyed). Approve with a note and **merge**. The merge is a push to `main`: run 4 plans both environments, saves the plans as artifacts, and `apply-staging` applies its saved plan: `Apply complete! Resources: 0 added, 0 changed, 0 destroyed.`

12. Priya tries to start the production apply herself (in her shell; use your run number):
    ```bash
    curl -s -X POST -H "Authorization: token $(cat ~/.gitea-token)" -H 'Content-Type: application/json' http://gitea:3000/api/v1/repos/allcsvideos/infra-production/actions/workflows/apply-prod.yml/dispatches -d '{"ref":"main","inputs":{"run":"4"}}'; echo
    exit
    ```
    `{"message":"not found",...}`: the repo is private to the releasers, so for her it does not exist.

13. **Rahul** runs **apply-prod** with run `4`. The log shows `approved by: rahul`, `run 4 on main, commit ...`, prints the downloaded saved plan (`us-east-1c`, `10.0.103.0/24`, `Plan: 1 to add`), then `terraform apply tfplan`:
    ```
    Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
    network = { "subnets" = { "us-east-1a" = "10.0.101.0/24", "us-east-1b" = "10.0.102.0/24", "us-east-1c" = "10.0.103.0/24" } ... }
    ```
    Exactly what Rahul read in the pull request: applied by a machine, approved by a person, recorded.

14. **A stale saved plan is refused** (as Asha, a scratch folder with local state):
    ```bash
    docker exec -it -u asha -w /home/asha tflab-team bash
    ```
    ```bash
    mkdir -p ~/stale && cd ~/stale
    printf 'variable "zones" { type = number }\nresource "terraform_data" "subnets" { input = var.zones }\n' > main.tf && terraform init -no-color > /dev/null && terraform apply -no-color -auto-approve -var zones=2 > /dev/null
    cat main.tf
    terraform plan -no-color -var zones=3 -out=tfplan | tail -1
    terraform apply -no-color -auto-approve -var zones=4 | tail -1
    terraform apply -no-color tfplan
    ```
    ```
    Error: Saved plan is stale
    The given plan file can no longer be applied because the state was changed by another operation
    after the plan was created.
    ```

15. **tflint** on the repository:
    ```bash
    cd ~/allcsvideos-infra && git switch -q main && git pull -q
    tflint --version
    tflint --recursive
    ```
    `TFLint version 0.64.0`, then 2 warnings in `modules/network/main.tf`: no `required_version`, and no version constraint for the `random` provider. (Try fixing them in a PR.)

### Mapping this to real AWS
- **Credentials:** no access keys in CI secrets. On GitHub, give the job `id-token: write` and use `aws-actions/configure-aws-credentials` with `role-to-assume` (OIDC, Module 8 Lesson 5).
- **Roles:** pull-request plans assume a **read-only** role; the apply role trusts only the `main` branch (OIDC claim conditions); production's role sits behind an approval.
- **Locking:** `concurrency` queues runs, and the backend lock stops two writers (`use_lockfile` on S3).
- **Ready-made:** Atlantis, HCP Terraform. Add policy checks (Checkov) and `terraform test` (`*.tftest.hcl`, since 1.6).

## Common mistakes
- Applying from laptops: personal credentials, no review, no record.
- Long-lived AWS access keys in CI secrets: use OIDC and short-lived role credentials.
- Reviewing one plan and applying another: apply the saved plan (`terraform apply tfplan`), not a fresh plan.
- One pipeline with production credentials on every branch: keep them behind `main` and an approval.
- Auto-applying to production with no review: staging may auto-apply; production waits for a person who read the plan.

## Clean up
- AWS: done in step 3 (`terraform destroy -target=module.staging_net`). If anything is left in `~/tf/net`, run `cd ~/tf/net && terraform destroy`.
- Local lab (from this folder on your laptop):
  ```bash
  bash lab/down.sh
  ```
  It removes the `tflab-*` containers, any leftover job containers, volumes, the network and the `tflab-team` image, then prints nothing if all is gone. Optionally remove the pulled images: `docker rmi gitea/gitea:28.1.0 gitea/runner:5.1.1 gitea/runner-images:ubuntu-24.04-v26.10.01 postgres:18.6-alpine3.24`.

## Next
[M11-L06 · Drift, Import and the Ecosystem](../m11-l06-drift-import-and-the-ecosystem/)
