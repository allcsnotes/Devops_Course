# M11-L01 · Why IaC
> Video: Module 11, Lesson 1. Watch it first, then follow along here.

## What you'll learn
- The six problems of click-ops: not repeatable, no review, no history, drift, snowflakes, "who changed this?"
- What infrastructure as code (IaC) gives you: version control, pull-request review, repeatable environments, living documentation, rebuild after disaster
- **Imperative** (list the steps) vs **declarative** (describe the result) and why declarative is **idempotent**
- The tool landscape: Terraform / OpenTofu, CloudFormation, Pulumi / AWS CDK (provisioning) vs Ansible (configuration); the 2023 BSL licence change and the OpenTofu fork
- The Terraform loop: **write, init, plan, apply** (and destroy), and how to read plan symbols `+`, `~`, `-/+`, `-`

## Before you start
- AWS CloudShell in **us-east-1** (as in Module 10), with this repo cloned.
- **Terraform v1.16.6** (the video's version). CloudShell may not have it; install that exact version:
  ```bash
  mkdir -p ~/bin && cd /tmp && curl -sSLO https://releases.hashicorp.com/terraform/1.16.6/terraform_1.16.6_linux_amd64.zip \
    && unzip -o terraform_1.16.6_linux_amd64.zip terraform -d ~/bin && cd - && terraform version
  ```
- CloudShell's home folder is only 1 GB. The video's first `init` failed with `no space left on device`; the fix was a plugin cache in `/tmp`:
  ```bash
  export TF_PLUGIN_CACHE_DIR=/tmp/tfcache && mkdir -p $TF_PLUGIN_CACHE_DIR
  ```

> **Cost: free / pennies.** One empty, versioned S3 bucket. Lessons 3 and 6 keep using this same project and bucket, so keep it if you continue; otherwise run the [Clean up](#clean-up) (`terraform destroy`).

## Files in this folder
| File | What it is |
|---|---|
| `hello/main.tf` | the 53-line project from the video: providers, two variables, a data source, `random_id`, a versioned S3 bucket, two outputs |

## Follow along
1. Make a working copy (lessons 3 and 6 continue in it) and check Terraform:
   ```bash
   mkdir -p ~/tf && cp -R Devops_Course/terraform/m11-l01-why-iac/hello ~/tf/hello && cd ~/tf/hello
   terraform version
   ls; cat main.tf
   ```
   `Terraform v1.16.6 on linux_amd64`. Read `main.tf` at overview level; lesson 2 goes through every line.

2. Initialise (downloads the providers, writes the lock file):
   ```bash
   terraform init -no-color
   ```
   You should see:
   ```
   - Installed hashicorp/aws v6.69.1 (signed by HashiCorp)
   - Installed hashicorp/random v3.9.1 (signed by HashiCorp)
   Terraform has created a lock file .terraform.lock.hcl ...
   Terraform has been successfully initialized!
   ```
   Newer 6.x/3.x versions may be picked for you today; the lock file then pins whatever was chosen. Commit `.terraform.lock.hcl`.

3. Two cheap checks:
   ```bash
   terraform fmt -check && echo formatted
   terraform validate -no-color
   ```
   `formatted`, then `Success! The configuration is valid.`

4. Plan and save it:
   ```bash
   terraform plan -no-color -out=tfplan
   ```
   Read the summary line first:
   ```
   # aws_s3_bucket.media will be created
     + tags     = { + "Name" = "media-dev" }
     + tags_all = { + "ManagedBy" = "terraform"  + "Name" = "media-dev"  + "Project" = "allcsvideos" }
   ...
   Plan: 3 to add, 0 to change, 0 to destroy.
   Saved the plan to: tfplan
   ```
   A saved plan contains your configuration and variable values: treat it as sensitive and never name it `*.tf`.

5. Apply exactly the reviewed plan (**creates an S3 bucket**, free/pennies; removed with `terraform destroy`):
   ```bash
   terraform apply -no-color tfplan
   ```
   The order comes from the references: `random_id` (0s), then the bucket (1s), then versioning (1s).
   ```
   Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
   bucket_name = "allcs-media-dev-506c01"
   ```
   Your suffix will differ.

6. Don't just trust Terraform, ask AWS:
   ```bash
   terraform output
   aws s3api get-bucket-versioning --bucket $(terraform output -raw bucket_name)
   ```
   `"Status": "Enabled"`.

7. Idempotency: plan again with no changes:
   ```bash
   terraform plan -no-color
   ```
   `No changes. Your infrastructure matches the configuration.`

8. A small change: add an `Owner` tag, plan, apply:
   ```bash
   sed -i "s/Name = \"media-\${var.env}\"/Name = \"media-\${var.env}\", Owner = \"asha\"/" main.tf; grep Owner main.tf; terraform plan -no-color
   terraform apply -no-color -auto-approve
   ```
   ```
   # aws_s3_bucket.media will be updated in-place
   ~ resource "aws_s3_bucket" "media" {
       ~ tags = { "Name" = "media-dev"  + "Owner" = "asha" }
   Plan: 0 to add, 1 to change, 0 to destroy.
   ```
   `-auto-approve` is fine in a throwaway sandbox right after reading the plan. Never type it by hand against production.

9. The dangerous one - **only plan it, do not apply**:
   ```bash
   terraform plan -no-color -var env=staging | tail -25
   ```
   ```
   # aws_s3_bucket_versioning.media must be replaced
   -/+ resource "aws_s3_bucket_versioning" "media" {
         ~ bucket = "allcs-media-dev-506c01" -> (known after apply) # forces replacement
   Plan: 2 to add, 0 to change, 2 to destroy.
     ~ bucket_name = "allcs-media-dev-506c01" -> "allcs-media-staging-506c01"
   ```
   This would **destroy** the dev bucket and make a new one, not add staging next to it. Separate environments need separate state (lesson 5).

| Symbol | Meaning |
|---|---|
| `+` | create |
| `~` | update in place |
| `-/+` | replace (destroy, then create) |
| `-` | destroy |

## Common mistakes
- Applying without reading the plan: check the summary line every time; any destroy or replace on something with data means stop and ask why.
- Mixing console changes with Terraform: the next apply quietly reverts the manual fix.
- `-auto-approve` by hand in production: in a pipeline, apply a saved, reviewed plan.
- Not committing the lock file: machines pick different provider versions and plans disagree.
- Treating replacement as harmless: `-/+` on a bucket or a database deletes the old one and its data.

## Clean up
Lessons 3 and 6 continue with this bucket and the `~/tf/hello` folder. If you are not continuing now:
```bash
cd ~/tf/hello && terraform destroy
```
Type `yes` after checking the plan says `3 to destroy`. The bucket is empty, so the destroy succeeds. Then `rm -rf ~/tf/hello` if you want.

## Next
[M11-L02 · HCL Basics](../m11-l02-hcl-basics/)
