# M11-L04 · Modules
> Video: Module 11, Lesson 4. Watch it first, then follow along here.

## What you'll learn
- A module is just **a folder of `.tf` files**: variables in, outputs out, resources inside (like a function)
- Root module vs child module; calling a module with a `module` block (`source`, inputs) and reading its outputs (`module.<name>.<output>`)
- Writing a small network module with `count`, `cidrsubnet` and a splat output (`aws_subnet.public[*].id`)
- Using a **registry module** (`terraform-aws-modules/vpc/aws`) safely: check the publisher, pin the version, read the plan
- The `count` vs `for_each` trap: removing one item from a `count` list shifts every index
- Good module design: small interface, sensible defaults, outputs for everything, **no provider blocks**, pinned versions, README and examples

## Before you start
- AWS CloudShell in **us-east-1**, Terraform v1.16.6, this repo cloned in your home folder (see [M11-L01](../m11-l01-why-iac/) for install and the `TF_PLUGIN_CACHE_DIR` tip).
- The `countlab/` part runs anywhere Terraform runs (your laptop or the `hashicorp/terraform:1.16.6` image, see [M11-L02](../m11-l02-hcl-basics/)), with no cloud credentials.

> **Cost: free.** The applied part is one VPC and two subnets (no NAT gateway, no instances); VPCs and subnets cost nothing.
> The registry module is only **planned**, never applied. Careful: in the build project the same module with `enable_nat_gateway = true` creates a NAT gateway (~US$0.045/hour + data, plus ~US$0.005/hour for its Elastic IP).
> Lesson 5 continues in this `~/tf/net` project. Clean up: `terraform destroy` (see [Clean up](#clean-up)).

## Files in this folder
| File | What it is |
|---|---|
| `net/main.tf` | the root module: provider, a call to the local `./modules/network`, a call to the registry VPC module `~> 6.0`, two outputs |
| `net/modules/network/main.tf` | the child module: 3 variables, `aws_vpc.this`, `count` public subnets at `cidrsubnet(var.cidr, 8, 101 + count.index)`, 2 outputs |
| `countlab/by_count/main.tf` | 3 zones in a list with `count` (local only, `terraform_data`) |
| `countlab/by_key/main.tf` | the same zones in a map with `for_each` |

## Follow along
1. Copy the project and read it:
   ```bash
   mkdir -p ~/tf && cp -R ~/Devops_Course/terraform/m11-l04-modules/net ~/tf/net && cd ~/tf/net
   find . -name "*.tf" | sort; cat modules/network/main.tf
   cat main.tf
   ```
   The child module has **no provider block**: it inherits the root's. `name = "allcs-${terraform.workspace}"` is `allcs-default` until lesson 5 adds workspaces.

2. Initialise: the registry module is downloaded, the local one is used in place:
   ```bash
   terraform init -no-color | grep -E "module|Installing|Installed|initialized"
   ls .terraform/modules; cat .terraform/modules/modules.json | head -c 400; echo
   ```
   ```
   Initializing modules...
   Downloading registry.terraform.io/terraform-aws-modules/vpc/aws 6.7.3 for vpc...
   - vpc in .terraform/modules/vpc
   - staging_net in modules/network
   - Installed hashicorp/aws v6.69.1 (signed by HashiCorp)
   ```
   You may get a newer 6.x module/provider today; `modules.json` records what was picked.

3. Plan the registry module only (a lab shortcut):
   ```bash
   terraform plan -no-color -target=module.vpc | tail -8
   ```
   Terraform itself warns: *"The -target option is not for routine use, and is provided only for exceptional situations..."*. Remove `| tail -8` to read the whole plan and see how many resources a few inputs create.

4. Apply only your own module (**free**: a VPC and two subnets):
   ```bash
   terraform apply -no-color -auto-approve -target=module.staging_net
   ```
   ```
   # module.staging_net.aws_subnet.public[0]   availability_zone = "us-east-1a"  cidr_block = "10.1.101.0/24"  Name = "allcs-default-public-0"
   # module.staging_net.aws_subnet.public[1]   availability_zone = "us-east-1b"  cidr_block = "10.1.102.0/24"
   # module.staging_net.aws_vpc.this           cidr_block = "10.1.0.0/16"  Name = "allcs-default"
   Plan: 3 to add, 0 to change, 0 to destroy.
   ...
   Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
   staging_subnets = [ "subnet-...", "subnet-..." ]
   staging_vpc = "vpc-..."
   ```

5. Outputs and addresses:
   ```bash
   terraform output
   terraform state list
   ```
   ```
   module.staging_net.aws_subnet.public[0]
   module.staging_net.aws_subnet.public[1]
   module.staging_net.aws_vpc.this
   ```

6. Check the subnet maths (`cidrsubnet` adds 8 bits to a /16, the last number picks the /24):
   ```bash
   echo 'cidrsubnet("10.1.0.0/16", 8, 101)' | terraform console
   echo 'cidrsubnet("10.1.0.0/16", 8, 102)' | terraform console
   ```
   `"10.1.101.0/24"` and `"10.1.102.0/24"`: the Module 4 address plan, in staging's range.

7. **The `count` trap** (local, no cloud). Apply 3 copies, then remove the first zone:
   ```bash
   cd ~/Devops_Course/terraform/m11-l04-modules/countlab/by_count
   cat main.tf
   terraform init -no-color > /dev/null; terraform apply -no-color -auto-approve | tail -1
   terraform state list
   terraform plan -no-color -var 'zones=["us-east-1b", "us-east-1c"]'
   ```
   ```
   # terraform_data.subnet[0] must be replaced    triggers_replace = "us-east-1a" -> "us-east-1b"
   # terraform_data.subnet[1] must be replaced    triggers_replace = "us-east-1b" -> "us-east-1c"
   # terraform_data.subnet[2] will be destroyed
   Plan: 2 to add, 0 to change, 3 to destroy.
   ```
   One zone removed, all three touched: everything shifted down one index.

8. **The same with `for_each`:**
   ```bash
   cd ../by_key
   cat main.tf
   terraform init -no-color > /dev/null; terraform apply -no-color -auto-approve | tail -1
   terraform state list
   terraform plan -no-color -var 'zones={ b = "us-east-1b", c = "us-east-1c" }'
   ```
   ```
   # terraform_data.subnet["a"] will be destroyed
   # (because key ["a"] is not in for_each map)
   Plan: 0 to add, 0 to change, 1 to destroy.
   ```
   Only the removed key changes. Use `count` for nearly identical copies, `for_each` when copies have distinct, stable keys.

### Checking a registry module (from the video, checked 21 October 2026)
`terraform-aws-modules/vpc/aws`: community module (no partner badge, `verified` false), ~223 million downloads, v6.7.3 published 18 September 2026. Before using any public module: who publishes it, is it maintained, open issues, read its inputs and defaults, **pin the version**, then **read the plan**. In the build project the same module produced 24 of the 39 planned resources, including a NAT gateway from one input: `enable_nat_gateway = true` (see [M11-B01](../m11-b01-provision-the-allcsvideos-aws-infrastructure-with-terraform/)).

## Common mistakes
- Unpinned module versions: a registry module without `version`, or a git source without `?ref=v1.2.0`, takes whatever is newest.
- The giant do-everything module with 80 inputs: keep modules focused.
- Hard-coded values (region, account, CIDR) inside a module make it single-use again.
- `count` over a list that changes: use `for_each` with stable keys.
- Using `-target` routinely: it hides the rest of the plan.
- A thin wrapper around one resource adds a layer and nothing else: use the resource directly.

## Clean up
Lesson 5 continues in `~/tf/net`; keep it if you continue (it is free). Otherwise:
```bash
cd ~/tf/net && terraform destroy        # destroys the 3 module.staging_net resources (module.vpc was never applied)
```
The `countlab` folders only hold local state (no cloud objects):
```bash
cd ~/Devops_Course/terraform/m11-l04-modules/countlab && rm -rf */.terraform* */terraform.tfstate*
```

## Next
[M11-L05 · Environments and Pipelines](../m11-l05-environments-and-pipelines/)
