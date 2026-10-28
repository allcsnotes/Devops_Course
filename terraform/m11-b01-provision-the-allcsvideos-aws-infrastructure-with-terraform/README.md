# M11-B01 · Provision the allcsvideos AWS Infrastructure with Terraform
> Video: Module 11, Build 1. Watch it first, then follow along here.

## What you'll learn
- The whole Module 10 stack as **234 lines of Terraform** in 7 files: a registry VPC module, three chained security groups, an ALB, ECS on EC2 with Auto Scaling, RDS Postgres 17 with a **managed password**, and a versioned S3 bucket
- **One command builds it** (39 resources, ~6.5 min) and **one command removes it** (~3.5 min), with state in S3 and `use_lockfile`
- A day-two change the code way (2 -> 3 tasks), and a drift check with `-detailed-exitcode`
- A pull-request pipeline that needs **no cloud credentials**: `fmt`, `init -backend=false`, `validate`, **tflint** (with the AWS ruleset) and **checkov** (with a baseline and a custom policy)
- Two staged mistakes the pipeline catches before any plan: an invalid instance type, and a database opened to `0.0.0.0/0`
- What changes at real scale (NAT per AZ, Multi-AZ RDS, HTTPS, placement strategy, capacity providers, split state) and how plan/apply would run from a pipeline with OIDC

## Before you start
- Everything from Module 11 so far, especially [M11-L03](../m11-l03-state/) (S3 backend) and [M11-L05](../m11-l05-environments-and-pipelines/) (the Gitea pipeline lab).
- **Part A (AWS):** AWS CloudShell in **us-east-1**, Terraform v1.16.6 (install steps in [M11-L01](../m11-l01-why-iac/)), this repo cloned in your home folder.
- The instance profile **`ecsInstanceRole`** must exist (made by hand in [M10-L06](../../cloud/m10-l06-serverless-and-managed-containers/); the code looks it up instead of creating it, because the video's sandbox only allowed that role name). If you deleted it:
  ```bash
  aws iam create-role --role-name ecsInstanceRole --assume-role-policy-document file://$HOME/Devops_Course/cloud/m10-l02-iam/trust-ec2.json
  aws iam attach-role-policy --role-name ecsInstanceRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role
  aws iam create-instance-profile --instance-profile-name ecsInstanceRole
  aws iam add-role-to-instance-profile --instance-profile-name ecsInstanceRole --role-name ecsInstanceRole
  ```
- **Part B (local):** Docker Desktop and a free port 3000 (stop the lesson 5 lab first: `bash ../m11-l05-environments-and-pipelines/lab/down.sh`).

> **Cost warning - this is the most expensive lab in Module 11.** While the stack is up (approx. us-east-1 unit prices from the AWS pricing pages, checked 21 October 2026; check the pricing calculator):
> - NAT gateway **US$0.045/hour** + US$0.045/GB, its Elastic IP US$0.005/hour
> - Application Load Balancer **US$0.0225/hour** + US$0.008 per LCU-hour (plus its public IPv4 addresses, US$0.005/hour each)
> - 2 x `t3.micro` ECS nodes, about US$0.0104/hour each
> - RDS `db.t3.micro` about **US$0.018/hour** + 20 GB gp3 storage; the managed secret about US$0.40/month prorated
> - S3 and the state bucket: pennies
>
> Roughly **US$0.13-0.15 per hour (about US$3.50 a day)**. **Run `terraform destroy` the same day** (step 9). Part B is local and free.
>
> Some sandbox/playground accounts require T-series instances in **standard** CPU credit mode. If yours does, add `credit_specification { cpu_credits = "standard" }` inside `aws_launch_template.ecs` in `ecs.tf` (the video's code does not have it).

## Files in this folder
| File | What it is |
|---|---|
| `allcsvideos-aws/versions.tf` | Terraform `>= 1.10`, aws `~> 6.0`, random `~> 3.6`, the **S3 backend** (`key = allcsvideos/prod/terraform.tfstate`, `use_lockfile`), provider with `default_tags` |
| `allcsvideos-aws/variables.tf` | `region`, `env` (`prod`), `app_image` (`public.ecr.aws/nginx/nginx:1.29-alpine`), `desired_tasks` (2) |
| `allcsvideos-aws/network.tf` | `terraform-aws-modules/vpc/aws ~> 6.0` (6 subnets, one NAT gateway, DB subnet group) + security groups `alb` -> `ecs_nodes` -> `db` |
| `allcsvideos-aws/alb.tf` | ALB, target group (health checks every 10 s, 10 s deregistration delay), HTTP listener |
| `allcsvideos-aws/ecs.tf` | data sources (ECS AMI from SSM, `ecsInstanceRole`), cluster, launch template (IMDSv2), ASG 2-4, task definition (bridge, `hostPort = 0`), service with `depends_on` the listener |
| `allcsvideos-aws/data.tf` | RDS Postgres 17 (`manage_master_user_password = true`), S3 bucket + versioning |
| `allcsvideos-aws/outputs.tf` | `url`, `db_endpoint`, `media_bucket`, `vpc_id` |
| `allcsvideos-aws/.terraform.lock.hcl` | the committed provider lock file |
| `allcsvideos-aws/.tflint.hcl` | tflint: recommended Terraform rules + AWS ruleset `0.49.0` |
| `allcsvideos-aws/.checkov.baseline` | the 32 known checkov findings (only new findings fail) |
| `allcsvideos-aws/policies/db_sg_no_cidr.yaml` | custom checkov policy `CKV2_ALLCS_1`: a `-db` security group never takes CIDR ingress |
| `allcsvideos-aws/.gitea/workflows/checks.yml` | the pipeline: `validate`, `tflint` (`ghcr.io/terraform-linters/tflint:v0.64.0`), `checkov` (`bridgecrew/checkov:3.3.30`) |
| `stage/variables.b1.tf`, `stage/ecs.b1.tf` | Priya's staged PR 1: `node_type` variable with the typo `t3.mirco` |
| `stage/network.b2.tf` | Priya's staged PR 2: port 5432 from `0.0.0.0/0` on the db group |
| `lab/up.sh`, `lab/down.sh`, `lab/image/`, `lab/runner/`, `lab/accounts.txt` | the local Gitea + runner lab (no cloud) |

## Follow along

### Part A - build, check, change and destroy (CloudShell)
1. Copy the project and use a plugin cache outside the 1 GB home folder (the video's first `init` failed with `no space left on device`):
   ```bash
   cp -R ~/Devops_Course/terraform/m11-b01-provision-the-allcsvideos-aws-infrastructure-with-terraform/allcsvideos-aws ~/allcsvideos-aws && cd ~/allcsvideos-aws
   export TF_PLUGIN_CACHE_DIR=/tmp/tfcache && mkdir -p $TF_PLUGIN_CACHE_DIR
   ls; wc -l *.tf | tail -1
   ```
   `234 total`.

2. A state bucket for this project (pennies; deleted in step 9), then fill in `versions.tf`:
   ```bash
   STATE=allcs-tfstate-$RANDOM$RANDOM; aws s3api create-bucket --bucket $STATE --query Location --output text; aws s3api put-bucket-versioning --bucket $STATE --versioning-configuration Status=Enabled; echo $STATE > ~/state_bucket
   sed -i "s/allcs-tfstate-CHANGE-ME/$(cat ~/state_bucket)/" versions.tf && grep bucket versions.tf
   ```

3. Init and validate:
   ```bash
   terraform init -no-color 2>&1 | grep -E "Initializing|Installing|Installed|module|successfully|Error"
   terraform validate -no-color
   ```
   ```
   Downloading registry.terraform.io/terraform-aws-modules/vpc/aws 6.7.3 for vpc...
   - Installed hashicorp/random v3.9.1 (signed by HashiCorp)
   - Installed hashicorp/aws v6.69.1 (signed by HashiCorp)
   Terraform has been successfully initialized!
   Success! The configuration is valid.
   ```

4. Plan, saved, and **read it** (this is the review):
   ```bash
   terraform plan -no-color -out=tfplan > plan.txt 2>&1; grep -E "will be created" plan.txt | sed "s/^ *# //" | head -60; grep -E "Plan:|Error" plan.txt
   ```
   15 resources from our files (`aws_autoscaling_group.ecs` ... `random_id.suffix`) and 24 from `module.vpc`, including `module.vpc.aws_nat_gateway.this[0]` and `module.vpc.aws_eip.nat[0]`:
   ```
   Plan: 39 to add, 0 to change, 0 to destroy.
   ```

5. Apply the saved plan (**billing starts now, ~US$0.13-0.15/hour**):
   ```bash
   time terraform apply -no-color tfplan > apply.txt 2>&1; grep -E "Creation complete|Apply complete|Error" apply.txt | sed -E "s/\[id=[^]]*\]//" | tail -45
   terraform output
   ```
   The slow ones: `aws_nat_gateway` 1m53s, `aws_lb.web` 2m11s, `aws_db_instance.main` 6m7s; in parallel, the whole apply was `real 6m23.804s`.
   ```
   Apply complete! Resources: 39 added, 0 changed, 0 destroyed.
   db_endpoint = "allcs-prod.<random>.us-east-1.rds.amazonaws.com"
   media_bucket = "allcs-prod-media-<hex>"
   url = "http://allcs-prod-<number>.us-east-1.elb.amazonaws.com"
   vpc_id = "vpc-..."
   ```

6. Is it really working?
   ```bash
   aws ecs wait services-stable --cluster allcs-prod --services web; aws ecs describe-services --cluster allcs-prod --services web --query "services[0].[runningCount,desiredCount]" --output text
   URL=$(terraform output -raw url); for i in $(seq 1 30); do C=$(curl -s -o /dev/null -w "%{http_code}" $URL); [ "$C" = "200" ] && break; sleep 10; done; echo "HTTP $C after $((i*10))s"; curl -sI $URL | head -3
   aws elbv2 describe-target-health --target-group-arn $(aws elbv2 describe-target-groups --names allcs-prod-web --query "TargetGroups[0].TargetGroupArn" --output text) --query "TargetHealthDescriptions[].[Target.Id,Target.Port,TargetHealth.State]" --output table
   ```
   `2 2`, `HTTP 200 after 10s` (the loop counts tries x 10; the first try answered), `HTTP/1.1 200 OK`, and two healthy targets. In the video both were on the **same instance** (ports 32768 and 32769): nothing asks ECS to spread them (see "At real scale").

7. State and drift check:
   ```bash
   terraform state list | wc -l; terraform state list | grep -v module.vpc
   terraform plan -no-color -detailed-exitcode > /dev/null; echo "plan exit code: $?"
   ```
   `41` (39 resources + 2 data sources) and `plan exit code: 0`.

8. Day two: three tasks instead of two:
   ```bash
   sed -i "s/default = 2/default = 3/" variables.tf; terraform plan -no-color | grep -E "~|desired_count|Plan:"
   terraform apply -no-color -auto-approve | grep -E "Modifications complete|Apply complete"
   aws ecs wait services-stable --cluster allcs-prod --services web; aws ecs describe-services --cluster allcs-prod --services web --query "services[0].[runningCount,desiredCount]" --output text
   ```
   `~ desired_count = 2 -> 3`, `Plan: 0 to add, 1 to change, 0 to destroy.`, then `3 3`.

9. **Destroy everything** (Part B below needs no AWS, so stop the bill now):
    ```bash
    time terraform destroy -no-color -auto-approve > destroy.txt 2>&1; grep -E "Destruction complete|Destroy complete|Error" destroy.txt | sed -E "s/\[id=[^]]*\]//" | tail -12
    terraform state list | wc -l
    aws ec2 describe-vpcs --filters Name=tag:Env,Values=prod --query "length(Vpcs)"
    ```
    `aws_ecs_service.web` 2m38s, the internet gateway 2m0s, `real 3m22.990s`, `Destroy complete! Resources: 39 destroyed.`, then `0` and `0` - no NAT gateway left behind. Then remove the state bucket:
    ```bash
    bash ~/Devops_Course/terraform/m11-l03-state/delete-state-bucket.sh
    ```

### Part B - the pull-request pipeline (local, no cloud)
10. Start the lab (on your laptop, from this folder):
    ```bash
    bash lab/up.sh
    ```

11. **Asha** pushes the project, then protects `main`:
    ```bash
    docker exec -it -u asha -w /home/asha tfci-team bash
    ```
    ```bash
    git clone -q http://gitea:3000/allcsvideos/allcsvideos-aws.git && cd allcsvideos-aws && cp -r /tmp/repo-src/. .
    tree -a -I '.git' --noreport
    wc -l *.tf | tail -1
    git add .
    git commit -qm 'allcsvideos AWS stack: VPC, ALB, ECS on EC2, RDS, S3 + PR checks'
    git push -q origin HEAD:main
    curl -s -X POST -H "Authorization: token $(cat ~/.gitea-token)" -H 'Content-Type: application/json' \
      http://gitea:3000/api/v1/repos/allcsvideos/allcsvideos-aws/branch_protections \
      -d '{"rule_name":"main","enable_push":false,"required_approvals":1,"enable_status_check":true,"status_check_contexts":["infra-checks / validate (pull_request)","infra-checks / tflint (pull_request)","infra-checks / checkov (pull_request)"],"block_on_rejected_reviews":true,"dismiss_stale_approvals":true}' | jq -c '{rule_name, enable_push, required_approvals}'
    exit
    ```
    Run 1 (**allcsvideos-aws -> Actions** at http://localhost:3000): `validate`, `tflint`, `checkov` all green. The first checkov run on this project found **32** issues (HTTP not HTTPS, single-AZ DB, no deletion protection...); `.checkov.baseline` records them so only **new** findings fail.

12. **Priya**, staged PR 1 - move the instance type into a variable (with a typo):
    ```bash
    docker exec -it -u priya -w /home/priya tfci-team bash
    ```
    ```bash
    git clone -q http://gitea:3000/allcsvideos/allcsvideos-aws.git && cd allcsvideos-aws
    git switch -q -c priya/node-type-variable
    cp /tmp/stage/variables.b1.tf variables.tf && cp /tmp/stage/ecs.b1.tf ecs.tf
    git diff
    git commit -qam 'ecs: node instance type as a variable'
    git push -q -u origin priya/node-type-variable
    curl -s -X POST -H "Authorization: token $(cat ~/.gitea-token)" -H 'Content-Type: application/json' \
      http://gitea:3000/api/v1/repos/allcsvideos/allcsvideos-aws/pulls \
      -d '{"head":"priya/node-type-variable","base":"main","title":"ecs: node instance type as a variable","body":"Moves the ECS node instance type into variables.tf (node_type), so environments can differ later. Same type as today."}' | jq -c '{number, title}'
    ```
    Run 2: `fmt`, `validate` and `checkov` pass (to Terraform it's just a string). **tflint fails**:
    ```
    Error: "t3.mirco" is an invalid value as instance_type (aws_launch_template_invalid_instance_type)
    ```
    Try to merge anyway:
    ```bash
    curl -s -X POST -H "Authorization: token $(cat ~/.gitea-token)" -H 'Content-Type: application/json' http://gitea:3000/api/v1/repos/allcsvideos/allcsvideos-aws/pulls/1/merge -d '{"Do":"merge"}'; echo
    ```
    `{"message":"Not all required status checks successful",...}`. Fix and push:
    ```bash
    sed -i 's/t3.mirco/t3.micro/' variables.tf
    git diff
    git commit -qam 'ecs: fix the node type typo'
    git push -q
    ```
    Run 3 is green. Log in as **rahul** in the browser, approve ("same instance type as before") and merge; run 4 on `main` is green.

13. **Priya**, staged PR 2 - "let the analytics laptop reach Postgres":
    ```bash
    git switch -q main && git pull -q && git switch -q -c priya/analytics-db-access
    cp /tmp/stage/network.b2.tf network.tf
    git diff
    git commit -qam 'db: let the analytics laptop reach Postgres'
    git push -q -u origin priya/analytics-db-access
    curl -s -X POST -H "Authorization: token $(cat ~/.gitea-token)" -H 'Content-Type: application/json' \
      http://gitea:3000/api/v1/repos/allcsvideos/allcsvideos-aws/pulls \
      -d '{"head":"priya/analytics-db-access","base":"main","title":"db: let the analytics laptop reach Postgres","body":"Opens 5432 so the analytics laptop can query the database."}' | jq -c '{number, title}'
    exit
    ```
    Run 5: **checkov fails** on the custom policy:
    ```
    Check: CKV2_ALLCS_1: "Database security groups accept only other security groups, never CIDR ranges"
        FAILED for resource: aws_security_group.db
        Severity: CRITICAL
    ```
    (On a busy laptop `validate` may time out starting the AWS provider; re-run the job.) As **rahul**, *request changes* ("a database never takes CIDR ingress; analytics needs a read replica or a bastion path"), and close the PR. Some changes shouldn't be fixed; they shouldn't exist.

### Plan and apply from a pipeline (design, not run in this lab)
The lab has no cloud credentials, and Gitea has no OIDC. In production: on every PR the same checks plus `terraform plan` with a **read-only IAM role via OIDC**, the plan posted to the PR (lesson 5); after merge, plan again on `main`, save the plan as an artifact, a person approves, and `terraform apply tfplan` runs with a separate apply role that trusts only `main`. The S3 backend's `use_lockfile` stops a second writer, and a nightly `plan -detailed-exitcode` watches for drift.

### At real scale
| Area | Lab | Production |
|---|---|---|
| NAT | `single_nat_gateway` | `one_nat_gateway_per_az` (doubles the NAT cost) |
| Database | single-AZ, `skip_final_snapshot` | `multi_az`, deletion protection, final snapshot, longer backups |
| Front door | HTTP :80 | HTTPS :443 with an ACM certificate, :80 redirects |
| Tasks | can land on one node | ordered placement strategy: spread by AZ, then instance |
| Nodes | fixed ASG 2-4 | ECS capacity provider with managed scaling |
| State | one state | one per environment and per component (network, data, compute) |

## Common mistakes
- Forgetting to destroy: a NAT gateway and an ALB bill every hour, used or not.
- Trusting `validate` alone: it can't see an invalid instance type or a database open to the world; add tflint and checkov.
- Fixing 32 checkov findings at once: baseline them, fail only on new ones, and work the list down.
- A single NAT gateway in production: one zone's bad day takes the other zone's way out with it.
- Applying from a laptop in a real team: plan and apply belong to a pipeline with OIDC and an approval.

## Clean up
1. AWS - if you have not done step 9 yet:
   ```bash
   cd ~/allcsvideos-aws && terraform destroy
   bash ~/Devops_Course/terraform/m11-l03-state/delete-state-bucket.sh
   ```
   Optionally delete `ecsInstanceRole` (see the [M10-L06 clean up](../../cloud/m10-l06-serverless-and-managed-containers/#clean-up)).
2. Local lab:
   ```bash
   bash lab/down.sh
   ```

## Next
[M12-L01 · Ansible Basics](../../ansible/m12-l01-ansible-basics/)
