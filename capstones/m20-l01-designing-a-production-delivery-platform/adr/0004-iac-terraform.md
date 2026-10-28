---
status: accepted
date: 2026-10-22
decision-makers: Asha, Rahul
consulted: Priya
informed: Meera
---

# Describe all AWS infrastructure in Terraform

## Context and Problem Statement

Networks, clusters, databases and accounts must be built
the same way for dev, staging and production, and every
change must be reviewed. Which tool describes them?

## Decision Drivers

* Plans reviewed in pull requests before any apply.
* Mature AWS provider and registry modules.
* A way out if the license or pricing changes.

## Considered Options

* Terraform
* OpenTofu
* Pulumi
* AWS CloudFormation

## Decision Outcome

Chosen option: "Terraform", because the team knows HCL, the
registry VPC and EKS modules fit us, and the same code runs
on OpenTofu if we ever need to switch.

### Consequences

* Good, because 39 resources came up from one reviewed plan.
* Bad, because Terraform is BSL licensed since 1.6 (2023).

### Confirmation

Every pull request runs fmt, validate, tflint and checkov,
and a nightly plan with -detailed-exitcode finds drift.

## Pros and Cons of the Options

### OpenTofu

* Good, because it is open source (MPL 2.0), under CNCF.
* Neutral, because new features differ from Terraform's.

### Pulumi

* Good, because infrastructure is written in Python or TS.
* Bad, because the team would learn a new model.

### AWS CloudFormation

* Good, because AWS runs the state for us.
* Bad, because it only covers AWS.

## More Information

Course: M11-L06, M11-B01, M19-L03.
