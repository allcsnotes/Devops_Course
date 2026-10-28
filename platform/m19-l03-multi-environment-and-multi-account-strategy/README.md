# M19-L03 · Multi-Environment and Multi-Account Strategy
> Video: Module 19, Lesson 3. Watch it first, then follow along here.

## What you'll learn
- Why a separate AWS account is the strongest boundary between dev, staging and prod (and why names, tags, networks and separate state are weaker)
- How AWS Organizations works: management account, member accounts, OUs, consolidated billing, SCPs and RCPs
- What a landing zone (AWS Control Tower) gives you: Log Archive and Audit accounts, controls, Account Factory / AFT
- How people (IAM Identity Center) and pipelines (OIDC + `sts:AssumeRole`) reach many accounts without long-lived keys
- Same Terraform code in every account with its own state, plus a guard that refuses the wrong account's credentials
- Build an image once and promote the same digest from dev to staging to prod through reviewed pull requests

## Before you start
- Docker Desktop (or Docker Engine) with about 3 GB free memory, git, and a terminal (macOS/Linux, or WSL/Git Bash on Windows).
- Internet access the first time: the lab pulls `gitea/gitea:28.1.0`, `registry:3.1.2`, `gitea/runner:5.1.1`,
  `gitea/runner-images:ubuntu-24.04-v26.10.01`, `hashicorp/terraform:1.16.6`, `gitea/tea:0.16.0`, `ubuntu:24.04`,
  `docker:29.5.3-cli`, `python:3.13.16-alpine3.23`, kustomize v5.8.3, and (for one step) the AWS provider 6.69.1.
- You do **not** need Terraform, kustomize or tea on your laptop: they are inside the lab's "laptop" container.
- Helpful background: environments (Module 9), Terraform per-environment folders (Module 11), GitOps with Argo CD
  (Module 15), IAM (Module 18). The **optional** AWS step needs an AWS account and CloudShell (read-only commands, no cost).

Nothing in this lab can create AWS accounts, so it is a **labelled stand-in**: three "accounts" are three separate
state folders with fake account numbers (111111111111, 222222222222, 333333333333), and three small agents stand in
for Argo CD in each account. The Terraform runs, the Git server, the branch protection, the CI check and the
promotions are all real.

## Files in this folder
| File | What it is |
|---|---|
| `infra/` | The `allcsvideos-infra` repo: `modules/platform` (stand-in module with an account guard) and `envs/{dev,staging,prod}` (backend, main, tfvars) |
| `infra/aws-example/main.tf` | The same idea on real AWS: `allowed_account_ids` + `assume_role` (validate only, never applied) |
| `api/` | The `allcsvideos-api` app repo at v1.8.0: a tiny stdlib Python API that reports its version, git commit and build time |
| `deploy/` | The `allcsvideos-deploy` GitOps repo: Kustomize base, one overlay per environment, `scripts/promotion-check.sh`, and the Gitea Actions workflow that runs it |
| `lab/up.sh` / `lab/down.sh` | Start / remove the whole lab (Gitea, registry, laptop, build box, runner, agents) |
| `lab/shell.sh` | Open a shell as `asha`, `priya`, `rahul` (the laptop) or `ci` (build-01) |
| `lab/laptop/` | Image for the team laptop, plus `lab-login` (stand-in for `aws sso login`) |
| `lab/agent/` | Image for the GitOps agents and the build box: `agent.sh` (reconcile loop), `build-image.sh` (the CI build step) |
| `lab/runner/config.yaml` | Gitea runner config |
| `lab/accounts.txt` | The lab's Gitea users and their FAKE passwords |

## Follow along

### 1. (Optional) See real guardrails from inside an AWS account
The video ran these read-only commands in AWS CloudShell, inside a training sandbox that is a member account of
someone else's organization. In your own account the answers will differ (a standalone account has no organization,
so you will see `AWSOrganizationsNotInUseException` instead of `AccessDeniedException`).

```bash
aws organizations describe-organization
aws organizations list-accounts
aws organizations list-policies --filter SERVICE_CONTROL_POLICY
aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text)
aws ec2 describe-availability-zones --region ap-south-1 --query 'AvailabilityZones[].[ZoneName,ZoneId]' --output table
aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=allcsvideos
aws ec2 describe-regions --query "Regions[].RegionName" --output text
aws ec2 describe-instances --region us-west-2 --query "length(Reservations)"
```

What the sandbox showed (account and organization ids masked):
```
aws: [ERROR]: An error occurred (AccessDeniedException) when calling the DescribeOrganization operation: You don't have permissions to access this resource.
...
User: arn:aws:iam::123456789012:user/lab-user is not authorized to perform: budgets:ViewBudget on resource: arn:aws:budgets::123456789012:budget/*
  with an explicit deny in a service control policy: arn:aws:organizations::123456789012:policy/o-exampleorg1/service_control_policy/p-examplescp1
...
User: arn:aws:iam::123456789012:user/lab-user is not authorized to perform: ec2:DescribeAvailabilityZones with an explicit deny in a service control policy: .../p-examplescp2
...
User: arn:aws:iam::123456789012:user/lab-user is not authorized to perform: tag:GetResources with an explicit deny in a service control policy: .../p-examplescp3
```
Three different SCPs, three different jobs. `describe-regions` still listed 17 regions and the read in `us-west-2`
answered `0`: which regions are enabled and what you may do in them are different questions.

From Module 18, the IAM policy simulator said `explicitDeny` for `organizations:LeaveOrganization`, which is consistent
with the SCP AWS recommends at the root:
```
|  organizations:LeaveOrganization |  explicitDeny  |
```

### 2. Start the lab
```bash
cd platform/m19-l03-multi-environment-and-multi-account-strategy/lab
./up.sh
```
It takes a few minutes the first time (image builds). It creates the Gitea users and teams, builds api **1.8.0** once,
writes that digest into all three overlays, pushes the deploy repo, protects `main`, and starts the runner and the
three agents. When it prints `lab up`, open http://localhost:3000 (users and fake passwords in `accounts.txt`).

### 3. The infra repo: one module, one folder per account
Open a shell as Asha and look around:
```bash
./shell.sh asha
cd ~/allcsvideos-infra
whoami; terraform version | head -1
tree -F --noreport -I aws-example
```
You should see `Terraform v1.16.6` and:
```
./
├── envs/
│   ├── dev/
│   │   ├── backend.tf
│   │   ├── main.tf
│   │   └── terraform.tfvars
│   ├── prod/ ...
│   └── staging/ ...
└── modules/
    └── platform/
        └── main.tf
```
Read `modules/platform/main.tf`: `terraform_data` stands in for a VPC, a cluster and a database, and the
`account_guard` resource has a **precondition**: the account the credentials belong to must be the account this
environment lives in.

Now compare staging and prod:
```bash
diff -r envs/staging envs/prod
```
Only two files differ: the backend (each account's own state) and the variables (account, network range, node size and
count, database class). The same module and the same code; only the size and the identity differ. That's parity.
```
< account_id  = "222222222222"
> account_id  = "333333333333"
< node_size   = "t3.medium"
> node_size   = "t3.large"
< node_count  = 2
> node_count  = 3
< db_multi_az = false
> db_multi_az = true
```

### 4. Apply each environment, signed in to its own account
`lab-login` stands in for an Identity Center sign-in: it only records which (fake) account the shell's credentials
belong to.
```bash
cd envs/dev
lab-login dev
terraform init | grep -E "Initializing the backend|successfully"
terraform apply -auto-approve | grep -vE "^\s*$"
```
You should see:
```
lab stand-in: credentials for account 111111111111 (allcs-dev), role Deploy, 1 hour
...
Plan: 4 to add, 0 to change, 0 to destroy.
...
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
Outputs:
summary = "dev in 111111111111: 1 x t3.small, db db.t4g.micro"
```
Then staging and prod (run `terraform init` once in each folder first):
```bash
cd ../staging && lab-login staging
terraform init >/dev/null
terraform apply -auto-approve | grep -E "Apply complete|summary ="
cd ../prod && lab-login prod
terraform init >/dev/null
terraform apply -auto-approve | grep -E "Apply complete|summary ="
```
```
summary = "staging in 222222222222: 2 x t3.medium, db db.t4g.small"
summary = "prod in 333333333333: 3 x t3.large, db db.t4g.medium multi-AZ"
```
Three state files, in three places (on AWS: a bucket in each account):
```bash
ls -1 /srv/tfstate/*/
```

### 5. The guard: prod credentials in the dev folder
Staged on purpose: this terminal is still signed in to prod. Go to dev and plan:
```bash
echo $LAB_ACCOUNT_NAME
cd ../dev
terraform plan; echo "exit code $?"
```
You should see:
```
allcs-prod
...
Error: Resource precondition failed
...
Credentials are for account 333333333333, but dev lives in 111111111111.
exit code 1
```
Nothing was touched. On real AWS the provider does this for you; validate the example (downloads the AWS provider,
creates nothing):
```bash
cd ~/allcsvideos-infra/aws-example
terraform init | grep -E "Installing|Installed|successfully"
terraform validate
```
```
- Installed hashicorp/aws v6.69.1 (signed by HashiCorp)
Success! The configuration is valid.
```
`allowed_account_ids` refuses any other account, and `assume_role` takes the deploy role in the target account.

### 6. The deploy repo and its protection
Read `deploy/`: a base and one overlay per environment. Each overlay pins the image **by digest**, sets replicas
(1 / 2 / 3) and merges its own config (log level). `lab/up.sh` set this protection on `main` through the Gitea API:
```
"enable_push": false,
"unprotected_file_patterns": "envs/dev/**",
"required_approvals": 1,
"approvals_whitelist_teams": ["releasers"],
"dismiss_stale_approvals": true,
"status_check_contexts": ["promotion-check / check (pull_request)"]
```
Nobody pushes to `main` directly except files under `envs/dev`. One approval, counted only from the team
`releasers` (Rahul). And `promotion-check` must pass. Read `deploy/scripts/promotion-check.sh`: staging may only
receive the digest dev runs on main, prod only what staging runs. Nothing is ever rebuilt.

Watch the agents in a second terminal (each is a stand-in for Argo CD in one account):
```bash
docker logs -f lab-agent-dev
```

### 7. Build once: api 1.9.0
Priya's change, made in build-01's checkout of the app repo (standing in for her push):
```bash
./shell.sh ci
sed -i '1s/(stdlib only)\. /(stdlib only). 1.9.0: course search answers faster. /' app.py
git commit -qam "api 1.9.0: faster course search" && git tag v1.9.0
git log --oneline -2
build-image 1.9.0
```
You should see (your commit id and digest will differ; note your digest):
```
d98b6d6 (HEAD -> main, tag: v1.9.0) api 1.9.0: faster course search
pushed localhost:5001/allcsvideos/api:1.9.0
digest sha256:da4ffaa97e80...
```

### 8. CI owns dev
Still in build-01, ci-bot sets the new digest in `envs/dev` and pushes straight to `main`, which the rule allows:
```bash
cd /work/allcsvideos-deploy/envs/dev
kustomize edit set image allcsvideos/api=localhost:5001/allcsvideos/api@sha256:<your 1.9.0 digest>
git commit -qam "dev: api 1.9.0" && git push -q origin main && git log --oneline -1
```
Seconds later the dev agent syncs: one pod on the new digest.
```
[dev] git aa9d635: envs/dev wants api@sha256:da4ffaa97e80 replicas=1 dev/DEBUG
[dev] synced: 1 running api@sha256:da4ffaa97e80
```
Check it from Asha's shell:
```bash
curl -s api.dev:8080/version | jq -c
```
```
{"version":"1.9.0","git":"d98b6d6","built":"2026-10-21T19:24:46Z","env":"dev","log_level":"DEBUG","pod":"dev-api-1"}
```

### 9. Promote to staging with a pull request
As Priya:
```bash
./shell.sh priya
git clone -q http://gitea:3000/allcsvideos/allcsvideos-deploy.git && cd allcsvideos-deploy
git log --oneline
awk '/digest:/{split(FILENAME,f,"/"); printf "%-8s %s\n", f[2], substr($3,1,19)}' envs/*/kustomization.yaml
git switch -c promote/staging-1.9.0
D=$(sed -n "s/.*digest: //p" envs/dev/kustomization.yaml)
cd envs/staging && kustomize edit set image allcsvideos/api=localhost:5001/allcsvideos/api@$D && cd ../..
git diff
git commit -qam "staging: api 1.9.0" && git push -q origin promote/staging-1.9.0
tea pr create --title "staging: api 1.9.0" --head promote/staging-1.9.0 --base main
```
`git diff` is one line: old digest out, new digest in. The PR is `#1`. As Rahul, read the check and approve:
```bash
./shell.sh rahul
tea pr 1 -r allcsvideos/allcsvideos-deploy
tea pr approve 1 "same digest dev runs, check green" -r allcsvideos/allcsvideos-deploy
```
```
✓ promotion-check / check (pull_request) ...: Successful in 2s
```
As Priya, merge:
```bash
tea pr merge 1 --style merge
git switch -q main && git pull -q && git log --oneline -3
```
`docker logs lab-agent-staging` shows two pods of the same digest.

### 10. Hotfix 1.9.1 lands in dev
In build-01:
```bash
cd /work/allcsvideos-api
sed -i '1s/faster\. /faster. 1.9.1: fixes the empty search crash. /' app.py
git commit -qam "api 1.9.1: fix empty search" && git tag v1.9.1
build-image 1.9.1
cd /work/allcsvideos-deploy/envs/dev && git pull -q
kustomize edit set image allcsvideos/api=localhost:5001/allcsvideos/api@sha256:<your 1.9.1 digest>
git commit -qam "dev: api 1.9.1" && git push -q origin main && git log --oneline -1
```

### 11. Staged mistake: hotfix straight to prod
As Priya, edit prod on `main` and push:
```bash
git pull -q && D=$(sed -n "s/.*digest: //p" envs/dev/kustomization.yaml)
cd envs/prod && kustomize edit set image allcsvideos/api=localhost:5001/allcsvideos/api@$D && cd ../..
git commit -qam "prod: api 1.9.1 hotfix" && git push origin main
```
```
remote: error: Not allowed to push to protected branch main
 ! [remote rejected] main -> main (pre-receive hook declined)
```
So she opens pull request 2 instead:
```bash
git switch -c hotfix/prod-1.9.1 && git push -q origin hotfix/prod-1.9.1
tea pr create --title "prod: api 1.9.1 hotfix" --head hotfix/prod-1.9.1 --base main
tea pr 2
tea pr merge 2 --style merge
```
```
❌ promotion-check / check (pull_request) ...: Failing after 8s
Error: failed to merge PR #2: the server refused the merge; check required status checks, requested reviews, or branch protection rules
```
The job log says `prod: sha256:62739e9... REFUSED, staging runs sha256:da4ffaa... on main`. Nothing untested reaches prod.

### 12. Do it properly: prod gets what staging runs
```bash
tea pr close 2
git switch -q main && git reset -q --hard origin/main && git switch -q -c promote/prod-1.9.0
D=$(sed -n "s/.*digest: //p" envs/staging/kustomization.yaml)
cd envs/prod && kustomize edit set image allcsvideos/api=localhost:5001/allcsvideos/api@$D && cd ../..
git diff --stat && git commit -qam "prod: api 1.9.0" && git push -q origin promote/prod-1.9.0
tea pr create --title "prod: api 1.9.0" --head promote/prod-1.9.0 --base main >/dev/null && tea pr ls
```
Asha approves (she is an admin, but not a releaser):
```bash
# as asha
tea pr approve 3 "looks good" -r allcsvideos/allcsvideos-deploy
# as priya
tea pr merge 3 --style merge
API=http://gitea:3000/api/v1/repos/allcsvideos/allcsvideos-deploy
curl -s -X POST -H "Authorization: token $(cat ~/.gitea-token)" -H "Content-Type: application/json" -d "{\"Do\":\"merge\"}" $API/pulls/3/merge | jq -r .message
```
```
Does not have enough approvals
```
Rahul reads the diff (one digest out, one in) and approves; then Priya merges:
```bash
# as rahul
tea pr 3 -r allcsvideos/allcsvideos-deploy
API=http://gitea:3000/api/v1/repos/allcsvideos/allcsvideos-deploy
curl -s -H "Authorization: token $(cat ~/.gitea-token)" $API/pulls/3.diff | grep -E "^(\+\+\+|[-+]-)"
tea pr approve 3 "same digest staging tested" -r allcsvideos/allcsvideos-deploy
# as priya
tea pr merge 3 --style merge && echo merged
git switch -q main && git pull -q && git log --oneline -4
```
The prod agent runs three pods of that digest.

### 13. The proof: same image in staging and prod
As Asha:
```bash
for e in dev staging prod; do curl -s api.$e:8080/version | jq -c "{env,version,git,built,log_level}"; done
```
```
{"env":"dev","version":"1.9.1","git":"d1346a0","built":"2026-10-21T19:28:17Z","log_level":"DEBUG"}
{"env":"staging","version":"1.9.0","git":"d98b6d6","built":"2026-10-21T19:24:46Z","log_level":"INFO"}
{"env":"prod","version":"1.9.0","git":"d98b6d6","built":"2026-10-21T19:24:46Z","log_level":"WARNING"}
```
Staging and prod: same version, same git commit, same build time to the second. Only the environment and log level differ.

### 14. Why never rebuild?
In build-01, build the same commit again:
```bash
cd /work/allcsvideos-api
git checkout -q v1.9.0 && git log --oneline -1
build-image 1.9.0
curl -s -o /dev/null -D - -H "Accept: application/vnd.oci.image.manifest.v1+json" registry.lab:5000/v2/allcsvideos/api/manifests/1.9.0 | grep -i docker-content-digest
```
A **new** digest (the build time alone changes it), and the tag `1.9.0` now points at the new one. Staging and prod
don't care: they pinned the digest.

## Common mistakes
- **Shared credentials across environments.** One key that reaches dev and prod turns every dev mistake into a prod incident.
- **A snowflake prod.** Hand-made changes that exist only in production, so staging stops predicting anything. Change everything through code.
- **Promoting by rebuilding.** The same commit gives a new digest. Promote the artifact you tested.
- **Many accounts and no automation.** Hand-made accounts drift. Vend them from code (Account Factory / AFT) with a baseline.
- **Workloads in the management account.** SCPs can't touch it, and it holds the keys to every account. Keep it nearly empty.

## Clean up
```bash
cd platform/m19-l03-multi-environment-and-multi-account-strategy/lab
./down.sh
```
This removes the lab containers (including the `lab-<env>-api-*` pods and runner job containers), volumes, the
`lab-net` network, the `lab-laptop` / `lab-agent` images, the `localhost:5001/allcsvideos/api` images, and the lab
tokens in `lab/secrets/`. The optional AWS step created nothing.

## Next
[M19-L04 · AI in DevOps](../m19-l04-ai-in-devops/)
