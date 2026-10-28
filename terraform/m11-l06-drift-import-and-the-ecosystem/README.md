# M11-L06 · Drift, Import and the Ecosystem
> Video: Module 11, Lesson 6. Watch it first, then follow along here.

## What you'll learn
- What **drift** is (reality moving away from code and state), where it comes from, and how every `plan` finds it
- Deciding each drift: **revert** (apply) or **adopt** (change the code in a PR); what `-refresh-only` does and doesn't do; `lifecycle { ignore_changes }`
- Finding drift on a schedule with `terraform plan -detailed-exitcode` (0 = clean, 1 = error, 2 = changes) - never auto-apply on drift
- Renaming safely with a **`moved`** block (vs `terraform state mv`)
- Adopting hand-made resources with an **`import`** block and `-generate-config-out`; forgetting with `state rm` / `removed`
- The ecosystem: **OpenTofu** (state encryption), Pulumi, CloudFormation/CDK, Crossplane - and how to choose

## Before you start
- The `~/tf/hello` project from [M11-L01](../m11-l01-why-iac/) with its state in S3 from [M11-L03](../m11-l03-state/), in AWS CloudShell (us-east-1, Terraform v1.16.6).
- The `lab/` part runs on your laptop with Docker (or local installs): `hashicorp/terraform:1.16.6` and `ghcr.io/opentofu/opentofu:1.13.1`. No cloud, no credentials.

> **Cost: free.** Only tags change on the existing S3 bucket, and the security group you import is free. At the end this lesson **destroys** the hello project's bucket; the S3 state bucket from lesson 3 is deleted last with `delete-state-bucket.sh` (see [Clean up](#clean-up)).

## Files in this folder
| File | What it is |
|---|---|
| `rename.tf` | `moved` block: `aws_s3_bucket.media` -> `aws_s3_bucket.course_media` |
| `import.tf` | `import` block for a hand-made security group (put its ID in) |
| `lab/rename/main.tf`, `lab/rename/moved.tf.txt` | local rename demo with `terraform_data` (copy `moved.tf.txt` to `moved.tf` when the step says so) |
| `lab/tofu-enc/main.tf` | OpenTofu state encryption with a **fake** passphrase |

## Follow along

### Drift (CloudShell)
1. Stage Priya's 2 a.m. console fix with one CLI command (it stands in for the console click, and replaces the **whole** tag set):
   ```bash
   cd ~/tf/hello
   aws s3api put-bucket-tagging --bucket $(terraform output -raw bucket_name) --tagging "TagSet=[{Key=Name,Value=media-dev},{Key=Owner,Value=priya-clickops}]" && echo changed in the console by hand
   ```

2. Asha's next plan shows the drift (real value on the left, code on the right):
   ```bash
   terraform plan -no-color | grep -vE "^$" | tail -20
   ```
   ```
   # aws_s3_bucket.media will be updated in-place
       ~ tags     = { "Name" = "media-dev"   ~ "Owner" = "priya-clickops" -> "asha" }
       ~ tags_all = { + "ManagedBy" = "terraform"   ~ "Owner" = "priya-clickops" -> "asha"   + "Project" = "allcsvideos" }
   Plan: 0 to add, 1 to change, 0 to destroy.
   ```
   The overwrite also deleted the two default tags, so they come back with `+`.

3. The refresh-only view (records reality in state, touches no resource, changes no code):
   ```bash
   terraform plan -no-color -refresh-only | tail -15
   ```
   `This is a refresh-only plan, so Terraform will not take any actions to undo these...`

4. Decide: the hotfix was temporary, so **revert** by applying:
   ```bash
   terraform apply -no-color -auto-approve | tail -4
   ```
   Tags are back to `Owner = asha` with `Project` and `ManagedBy` restored.

5. Drift detection for a scheduled job:
   ```bash
   terraform plan -no-color -detailed-exitcode > /dev/null; echo "plan exit code: $?"
   ```
   `plan exit code: 0` (clean). Exit `2` means changes (drift or unapplied code), `1` means the job broke. A nightly job alerts on 2 and never auto-applies.

### Rename with `moved`
6. Locally first, to see the danger without AWS (from this folder on your laptop; use the Docker alias from [M11-L02](../m11-l02-hcl-basics/) if you have no local Terraform):
   ```bash
   cd lab/rename
   cat main.tf
   terraform init -no-color > /dev/null; terraform apply -no-color -auto-approve | tail -1
   sed -i 's/"media"/"course_media"/' main.tf; terraform plan -no-color
   terraform plan -no-color -detailed-exitcode > /dev/null; echo "plan exit code: $?"
   ```
   ```
   # terraform_data.course_media will be created
   # terraform_data.media will be destroyed
   # (because terraform_data.media is not in configuration)
   Plan: 1 to add, 0 to change, 1 to destroy.
   plan exit code: 2
   ```
   (macOS `sed`: `sed -i ''`.) Now add the `moved` block:
   ```bash
   cp moved.tf.txt moved.tf; cat moved.tf; terraform plan -no-color
   terraform plan -no-color -detailed-exitcode > /dev/null; echo "plan exit code: $?"
   terraform apply -no-color -auto-approve | tail -2; terraform plan -no-color -detailed-exitcode > /dev/null; echo "plan exit code: $?"
   ```
   ```
   # terraform_data.media has moved to terraform_data.course_media
   Plan: 0 to add, 0 to change, 0 to destroy.
   plan exit code: 2          <- a move is still a state change
   Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
   plan exit code: 0
   ```

7. The real bucket in CloudShell: rename in `main.tf`, add `rename.tf`, plan and apply:
   ```bash
   cd ~/tf/hello
   cp ~/Devops_Course/terraform/m11-l06-drift-import-and-the-ecosystem/rename.tf .
   sed -i "s/aws_s3_bucket\" \"media\"/aws_s3_bucket\" \"course_media\"/; s/aws_s3_bucket.media/aws_s3_bucket.course_media/g" main.tf; cat rename.tf; grep -n course_media main.tf
   terraform plan -no-color | grep -E "moved|has moved|Plan:|No changes"
   terraform apply -no-color -auto-approve | grep -E "moved|Apply complete"
   ```
   ```
   # aws_s3_bucket.media has moved to aws_s3_bucket.course_media
   Plan: 0 to add, 0 to change, 0 to destroy.
   Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
   ```

### Adopt a hand-made resource with `import`
8. The video imported `allcs-alb`, the security group built by hand in [M10-L03](../../cloud/m10-l03-vpc-networking/). If you deleted that network, make a stand-in by hand in your default VPC (**free**; you delete it in Clean up):
   ```bash
   SG=$(aws ec2 create-security-group --group-name allcs-alb --description "ALB from the internet" --query GroupId --output text)
   aws ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null; echo $SG
   ```
   (If the Module 10 group still exists: `SG=$(aws ec2 describe-security-groups --filters Name=group-name,Values=allcs-alb --query "SecurityGroups[0].GroupId" --output text)`.)
   Then fill in the import block:
   ```bash
   cp ~/Devops_Course/terraform/m11-l06-drift-import-and-the-ecosystem/import.tf . && sed -i "s/sg-CHANGE-ME/$SG/" import.tf
   cat import.tf
   ```

9. Let Terraform draft the resource block, and plan the import:
   ```bash
   terraform plan -no-color -generate-config-out=generated.tf | grep -E "import|Plan:|generated" ; head -25 generated.tf
   ```
   ```
   aws_security_group.alb: Preparing import... [id=sg-...]
     # (imported from "sg-...")
   Plan: 1 to import, 0 to add, 1 to change, 0 to destroy.
   # __generated__ by Terraform
   # Please review these resources and move them into your main configuration files.
   resource "aws_security_group" "alb" {
     description = "ALB from the internet"
     egress = [{ ... every field spelled out ... }]
   ```
   `1 to change` = the provider's `default_tags` being added. Generated config is a faithful copy, not good code: review and clean it before merging.

10. Apply the import and check state:
    ```bash
    terraform apply -no-color -auto-approve | grep -E "Import|imported|Apply complete"
    terraform state list
    ```
    `Apply complete! Resources: 1 imported, 0 added, 1 changed, 0 destroyed.` and `aws_security_group.alb` next to `aws_s3_bucket.course_media`.

11. Forget the group (it belongs to another project), then destroy the hello project:
    ```bash
    terraform state rm aws_security_group.alb; rm import.tf generated.tf; terraform destroy -no-color -auto-approve | tail -3
    ```
    ```
    Removed aws_security_group.alb
    Successfully removed 1 resource instance(s).
    Destroy complete! Resources: 3 destroyed.
    ```
    `state rm` only **forgets**: the security group still exists in AWS (see Clean up).

### OpenTofu (local)
12. State encryption, in OpenTofu's official image (from this folder on your laptop):
    ```bash
    cd lab/tofu-enc
    docker run --rm -it -v "$PWD":/work -w /work --entrypoint sh ghcr.io/opentofu/opentofu:1.13.1
    ```
    inside it:
    ```bash
    tofu version
    cat main.tf
    tofu init -no-color | grep -vE '^$'
    tofu apply -no-color -auto-approve | tail -1
    head -c 330 terraform.tfstate; echo
    tofu state list
    exit
    ```
    `OpenTofu v1.13.1`, then state whose resources sit in `"encrypted_data"` (only `serial`, `lineage` and key metadata are readable).

13. Terraform cannot read that configuration:
    ```bash
    docker run --rm -v "$PWD":/work -w /work hashicorp/terraform:1.16.6 init -no-color
    ```
    `Error: Unsupported block type ... Blocks of type "encryption" are not expected here.` Use one OpenTofu-only feature and your code is OpenTofu code.

## Key ideas: the IaC ecosystem
| | Terraform / OpenTofu | Pulumi | CloudFormation (+ CDK) | Crossplane |
|---|---|---|---|---|
| Language | HCL | TypeScript, Python, Go, .NET, Java, YAML | YAML/JSON (CDK: real languages) | Kubernetes YAML |
| State | file you store and lock | Pulumi Cloud or self-managed backend | kept by AWS | Kubernetes API |
| Multi-cloud | yes | yes | AWS only | yes |
| Preview | `plan` | `preview` | change sets | none (continuous) |
| Drift | every plan | `refresh` | built-in detection | corrected continuously |
| Licence | BSL 1.1 / MPL 2.0 | Apache 2.0 | AWS service (CDK Apache 2.0) | Apache 2.0 |

## Common mistakes
- Ignoring drift until an apply reverts a hotfix: run a scheduled plan, and decide every drift.
- Renaming without `moved`: 1 to add, 1 to destroy - data loss on a bucket or database.
- Trusting generated config blindly: it tells you to review it.
- Importing everything into one giant state: import into the right component/environment state.
- Thinking `state rm` deleted something: it only forgets; the resource keeps running and costing.

## Clean up
1. The hello project was destroyed in step 11. Delete the security group you created by hand in step 8 (skip if it is the Module 10 group and you still need it):
   ```bash
   aws ec2 delete-security-group --group-id $SG
   ```
2. Delete the S3 state bucket from lesson 3 (all versions):
   ```bash
   bash ~/Devops_Course/terraform/m11-l03-state/delete-state-bucket.sh
   rm -rf ~/tf/hello
   ```
3. Local lab files:
   ```bash
   cd lab && rm -rf */.terraform* */terraform.tfstate* rename/moved.tf && git checkout -- rename/main.tf
   ```

## Next
[M11-B01 · Provision the allcsvideos AWS Infrastructure with Terraform](../m11-b01-provision-the-allcsvideos-aws-infrastructure-with-terraform/)
