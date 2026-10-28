# M20-L01 · Designing a Production Delivery Platform
> Video: Module 20, Lesson 1. Watch it first, then follow along here.

This is mostly a design lesson. The hands-on part is small: you read four
architecture decision records (ADRs), a one-page reference architecture, and run a
tiny Python checker that a CI job could use to block a badly written ADR.

## What you'll learn
- Write the requirements down before choosing any tool: users, SLOs, team size, compliance and budget.
- Pick the simplest thing that meets them, and sort decisions into one-way and two-way doors.
- The twelve layers of a delivery platform, each with a decision, an alternative, and when to switch.
- How to record the big decisions as ADRs in the MADR 4.0.0 format, and check them automatically.
- A phased roadmap (week one, month one, quarter one, later) and the five DORA metrics as the scorecard.

## Before you start
- Python 3 (any recent 3.x; the video used `python:3.13.16-alpine3.23`). No extra packages.
- `tree` is optional (`ls -R adr` does the same job).
- No earlier lesson folder is needed. The ADRs refer back to builds from modules 9-19.

## Files in this folder
| File | What it is |
|------|------------|
| `adr/0001-ci-on-github-actions.md` | ADR: CI on GitHub Actions |
| `adr/0002-runtime-eks.md` | ADR: move the services from VMs to Amazon EKS (the one opened in the video) |
| `adr/0003-gitops-argo-cd.md` | ADR: GitOps delivery with Argo CD and Argo Rollouts |
| `adr/0004-iac-terraform.md` | ADR: infrastructure as code with Terraform |
| `drafts/0005-service-mesh.md` | A draft ADR that is deliberately incomplete, so the checker fails it |
| `reference-architecture.md` | The one-page reference architecture: requirements, 12 layers, scorecard |
| `check_adr.py` | Checks ADR files against the MADR 4.0.0 rules; exit code 1 if any fail |

## Follow along
1. Go into this folder and list the decision records.
   ```bash
   cd capstones/m20-l01-designing-a-production-delivery-platform
   tree adr
   ```
   You should see:
   ```
   adr
   ├── 0001-ci-on-github-actions.md
   ├── 0002-runtime-eks.md
   ├── 0003-gitops-argo-cd.md
   └── 0004-iac-terraform.md

   1 directory, 4 files
   ```

2. Open the runtime decision, `adr/0002-runtime-eks.md`, in VS Code. Find each part the video walks through:
   front matter (status, date, decision-makers, consulted, informed), the title, Context and Problem Statement,
   Decision Drivers, Considered Options, Decision Outcome with Consequences and Confirmation, and
   Pros and Cons of the rejected options.

3. Count the lines of the design.
   ```bash
   wc -l adr/*.md reference-architecture.md
   ```
   You should see a total of `282`.

4. Check the four ADRs.
   ```bash
   python3 check_adr.py adr/*.md; echo "exit code: $?"
   ```
   You should see:
   ```
   ok   0001-ci-on-github-actions.md  accepted, 3 options
   ok   0002-runtime-eks.md  accepted, 3 options
   ok   0003-gitops-argo-cd.md  accepted, 3 options
   ok   0004-iac-terraform.md  accepted, 4 options
   4 of 4 ADRs follow MADR 4.0.0
   exit code: 0
   ```

5. Check the draft service-mesh ADR. It has no Decision Outcome and only one option.
   ```bash
   python3 check_adr.py drafts/0005-service-mesh.md; echo "exit code: $?"
   ```
   You should see:
   ```
   FAIL 0005-service-mesh.md: missing Decision Outcome, options
   0 of 1 ADRs follow MADR 4.0.0
   exit code: 1
   ```
   Exit code 1 is what lets a CI job block the pull request.

6. Open `reference-architecture.md`: the requirements on top, then one row per layer with the decision,
   the alternative, and when to choose the alternative.

## Key ideas

**Three rules.** Requirements first. The simplest thing that meets them. Sort decisions by how hard they are
to undo: two-way doors (CI tool, dashboard, alert rule) decide fast; one-way doors (database, account layout,
runtime) slow down and get an ADR.

**The twelve layers** (what the course picked, and the main alternative):

| Layer | Picked | Alternative, and when |
|-------|--------|-----------------------|
| 1 Source | Trunk-based, PR + review, protected main | GitFlow: versioned releases on a schedule |
| 2 CI | GitHub Actions syntax + security gates | GitLab CI (code on GitLab), Jenkins (own servers, plugins) |
| 3 Artifacts | One image, built once, SBOM, provenance, cosign, deploy by digest | None worth taking |
| 4 Infrastructure | Terraform, one folder per env, separate AWS accounts | OpenTofu (license), Pulumi (Python/TS); one account for one team |
| 5 Runtime | EKS | ECS on EC2 or VMs from images: one team, few services |
| 6 Delivery | Argo CD + Argo Rollouts canary with analysis | Flux: terminal-first team |
| 7 Secrets | Vault + External Secrets Operator | AWS Secrets Manager: all-in on AWS |
| 8 Observability | Prometheus, Loki, Tempo, one Grafana | Managed Prometheus / Grafana Cloud: nobody can run storage |
| 9 Reliability | PITR backups, multi-AZ DB, DR from RTO/RPO, game days | Backups only ... warm standby; never skip the restore test |
| 10 Security | Least-privilege IAM, RBAC, policy as code, Kyverno admission | OPA Gatekeeper: you already write Rego |
| 11 Cost | Default tags, budgets, rightsizing, OpenCost | Read the bill: small, flat spend |
| 12 Platform | Backstage golden-path template | Thinnest viable platform: a wiki page + one template |

**Runtime is the biggest one-way door.** VMs with Ansible work, but canaries and admission are your own scripts.
ECS has no control-plane charge and (since October 2025) built-in canary and linear deploys, but not the
Kubernetes ecosystem. EKS gives GitOps, canaries and signed-only admission for $0.10/hour plus an upgrade
roughly every 14 months. For one team and a few services, start on ECS or VMs; move to Kubernetes when it pays.

**Roadmap.** Week one: Git with a protected main, a pipeline that builds/tests/scans one image, Terraform with
remote state, database backups on. Month one: staging and approved promotion, a managed runtime, a secrets
manager, golden signals on one dashboard, one SLO, tags and budgets. Quarter one: signed images and admission,
tracing, a restore drill and game day, separate accounts; Kubernetes/GitOps/canaries only if the requirements ask.
Later: golden path and portal when several teams need the same thing.

**DORA scorecard** (five metrics): change lead time, deployment frequency, failed deployment recovery time,
change fail rate, deployment rework rate. Track per team, over months, against the team's own past.

## Common mistakes
- Resume-driven architecture: choosing a tool because it looks good on a CV. Ask which requirement it meets and write it in an ADR.
- Building the platform before the product: a portal, a mesh and three clusters for one service with no users.
- Kubernetes by default: one team with three services may never need it.
- Copying big-tech setups: copy their reasoning, not their diagram.

## Try it yourself
1. Fix `drafts/0005-service-mesh.md` so it passes `check_adr.py`: add a second option and a Decision Outcome
   (even if the outcome is "not now"). Re-run the checker and get exit code 0.
2. Write `adr/0005-secrets-vault.md` for layer 7 in the same format, with AWS Secrets Manager as an option.
3. Answer the interview question out loud in five minutes: "Design a delivery platform for a company like
   allcsvideos" - requirements, then the layers with one alternative each, then the roadmap and DORA.

## Clean up
Nothing to clean up: this lesson only reads files. If you edited the ADRs, `git checkout -- .` in this folder restores them.

## Next
[M20-B01 · Zero-Downtime Migration from VMs to Kubernetes](../m20-b01-zero-downtime-migration-from-vms-to-kubernetes/)
