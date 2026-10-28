# M11-L02 · HCL Basics
> Video: Module 11, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- HCL grammar: **blocks** (type, labels, body), **arguments** and **expressions**, interpolation `${ }`, nested blocks, comments
- The `terraform` block: `required_version`, `required_providers`, the pessimistic constraint `~>`, and the lock file
- The `provider` block and `default_tags` (where `tags_all` comes from)
- Resources vs data sources, resource **addresses**, arguments vs attributes, and how **references build the dependency graph**
- Variables (types, validation, `sensitive`, precedence), locals, outputs, built-in functions, a first look at `count` and `for_each`

## Before you start
- The project from [M11-L01](../m11-l01-why-iac/) (this lesson reads its `main.tf`; a copy is in `lab/hello/`).
- **Local, on your laptop, no cloud account needed** for every hands-on step here. Either install **Terraform v1.16.6**, or use the official image with Docker:
  ```bash
  alias terraform='docker run --rm -i -v "$PWD":/work -w /work -e TF_VAR_db_password -e TF_VAR_env hashicorp/terraform:1.16.6'
  terraform version
  ```
  (On Linux, files the container creates are owned by root; `sudo rm -rf .terraform` when you tidy up.)

**Cost: free.** Nothing in this lesson touches AWS. `lab/hello` only downloads providers and draws a graph.

## Files in this folder
| File | What it is |
|---|---|
| `lab/pin/versions.tf` | asks for Terraform `>= 1.17` on purpose, to see the version error |
| `lab/vars/variables.tf` | `env` with a validation rule, `db_password` marked `sensitive` |
| `lab/vars/main.tf` | `locals`, and outputs using interpolation and `merge` (the `db_password` output is missing `sensitive = true` on purpose) |
| `lab/fns/messy.tf` | badly formatted on purpose, for `terraform fmt -diff` |
| `lab/loops/main.tf` | `count` vs `for_each` with the built-in `terraform_data` resource |
| `lab/hello/main.tf` | the lesson 1 project, for `terraform graph` and the lock file |

## Follow along
1. **Version constraints.** Ask for a newer Terraform than you have:
   ```bash
   cd lab/pin
   cat versions.tf; terraform init -no-color
   ```
   ```
   Error: Unsupported Terraform Core version
   This configuration does not support Terraform version 1.16.6.
   ```
   `~> 6.0` means `>= 6.0, < 7.0` (only the right-most part may grow). `>=` alone has no upper bound.

2. **Variables, locals and a sensitive output.** Set a fake password and plan:
   ```bash
   cd ../vars
   export TF_VAR_db_password=demo-password-123
   terraform init -no-color
   terraform plan -no-color
   ```
   ```
   Error: Output refers to sensitive values
     on main.tf line 14:
     14: output "db_password" {
   ```
   Fix it the way the message says, then let `fmt` realign the file:
   ```bash
   sed -i '/value = var.db_password/a sensitive = true' main.tf; terraform fmt; tail -4 main.tf
   terraform plan -no-color
   ```
   (macOS `sed`: use `sed -i ''` or just add `sensitive = true` inside the `db_password` output with your editor.)
   ```
   Changes to Outputs:
     + bucket_name = "allcs-dev-media"
     + db_password = (sensitive value)
     + tags        = { + Env = "dev"  + Name = "media-dev"  + Project = "allcsvideos" }
   ```

3. **Outputs.** Apply (only saves outputs, no real infrastructure), then read them:
   ```bash
   terraform apply -no-color -auto-approve
   terraform output
   terraform output -raw bucket_name; echo
   terraform output -raw db_password; echo
   ```
   `terraform output` shows `db_password = <sensitive>`, but `-raw db_password` prints `demo-password-123`. `sensitive` hides values from plans and logs; it does **not** encrypt them, and they are stored in state (lesson 3).

4. **Variable precedence** with `terraform console`:
   ```bash
   echo 'local.name_prefix' | terraform console
   echo 'env = "staging"' > terraform.tfvars
   echo 'local.name_prefix' | terraform console
   echo 'local.name_prefix' | TF_VAR_env=prod terraform console
   echo 'local.name_prefix' | terraform console -var env=prod
   ```
   `"allcs-dev"`, `"allcs-staging"`, `"allcs-staging"` (tfvars beats the environment variable), `"allcs-prod"` (the flag wins).
   Lowest to highest: default, `TF_VAR_` env vars, `terraform.tfvars`, `terraform.tfvars.json`, `*.auto.tfvars`, then `-var` / `-var-file`.

5. **Validation** stops a typo at the door:
   ```bash
   terraform plan -no-color -var env=qa
   ```
   ```
   Error: Invalid value for variable
     │ var.env is "qa"
   env must be dev, staging or prod.
   ```

6. **Built-in functions** in the console (any empty folder works):
   ```bash
   echo 'cidrsubnet("10.0.0.0/16", 8, 1)' | terraform console
   echo 'cidrsubnet("10.0.0.0/16", 8, 101)' | terraform console
   echo 'length(["us-east-1a", "us-east-1b", "us-east-1c"])' | terraform console
   echo 'slice(["us-east-1a", "us-east-1b", "us-east-1c"], 0, 2)' | terraform console
   echo 'merge({ Project = "allcsvideos" }, { Name = "media-dev" })' | terraform console
   ```
   `"10.0.1.0/24"`, `"10.0.101.0/24"`, `3`, the first two zones, and one merged map (on a duplicate key the later map wins).

7. **`count` vs `for_each`:**
   ```bash
   cd ../loops
   terraform init -no-color > /dev/null; terraform plan -no-color
   ```
   ```
   # terraform_data.by_count[0]  input = "10.0.1.0/24"
   # terraform_data.by_count[1]  input = "10.0.2.0/24"
   # terraform_data.by_key["us-east-1a"]  input = "subnet in us-east-1a"
   # terraform_data.by_key["us-east-1b"]  input = "subnet in us-east-1b"
   Plan: 4 to add, 0 to change, 0 to destroy.
   ```
   Remove the first zone from a `count` list and every index shifts; `for_each` keys stay stable.

8. **Formatting:**
   ```bash
   cd ../fns
   terraform fmt -diff
   ```
   The diff shows two-space indents and lined-up `=` signs. Run `fmt` before every commit.

9. **The dependency graph and the lock file** (downloads the AWS provider, no credentials needed):
   ```bash
   cd ../hello
   terraform init -no-color
   terraform validate -no-color
   terraform graph
   cat .terraform.lock.hcl
   ```
   ```
   "aws_s3_bucket.media" -> "random_id.suffix";
   "aws_s3_bucket_versioning.media" -> "aws_s3_bucket.media";
   ```
   The data source has no arrows. The lock file records the exact version picked (the video: `version = "6.69.1"`, `constraints = "~> 6.0"`, plus checksums).

10. **Break a reference on purpose** - type the bucket name as a plain string:
    ```bash
    sed -i 's/bucket = aws_s3_bucket.media.id/bucket = "allcs-media-dev-506c01"/' main.tf; grep -n 'bucket =' main.tf; terraform graph | grep -- '->'
    ```
    Only one arrow is left: versioning no longer waits for the bucket, so on a fresh apply it could run first and fail. Put it back with `git checkout lab/hello/main.tf` (or undo the edit).

### Data sources in the build project (shown in the video, from the sandbox)
The Module 11 build reads things it must not create: `data.aws_ssm_parameter.ecs_ami` (the ECS-optimized AMI ID, never hard-coded) and `data.aws_iam_instance_profile.ecs` (the `ecsInstanceRole` made by hand in Module 10). See [M11-B01](../m11-b01-provision-the-allcsvideos-aws-infrastructure-with-terraform/).

## Common mistakes
- Unpinned provider versions: use `~>` and commit the lock file.
- Hard-coded values that should be inputs (even the build project hard-codes `us-east-1a`/`us-east-1b`; a data source + `slice` would make it portable).
- Secrets in `tfvars` files committed to git: use a secrets manager or CI secret, and gitignore any tfvars that holds one.
- Referring by name instead of by attribute: you lose the dependency (step 10).
- Overusing `depends_on`: a last resort for dependencies no argument expresses (the build project has exactly one: the ECS service on the listener).

## Clean up
Everything was local. Remove the generated files if you like:
```bash
cd lab && rm -rf */.terraform */.terraform.lock.hcl */terraform.tfstate* vars/terraform.tfvars
git checkout -- .   # undo the sed edits in vars/main.tf and hello/main.tf
unset TF_VAR_db_password
```

## Next
[M11-L03 · State](../m11-l03-state/)
