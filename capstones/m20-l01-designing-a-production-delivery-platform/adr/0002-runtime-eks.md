---
status: accepted
date: 2026-10-22
decision-makers: Asha, Rahul
consulted: Priya, Meera
informed: everyone
---

# Move the allcsvideos services from VMs to Amazon EKS

## Context and Problem Statement

The services run on a VM fleet configured by Ansible. Three
teams now ship to it, and we want canary releases with
automatic rollback. Where should the services run?

## Decision Drivers

* Canary releases with rollback on SLO burn.
* Only signed images may run (admission policy).
* Self-healing and rolling updates without our own scripts.
* Two platform engineers to operate it.

## Considered Options

* Stay on VMs with Ansible
* Amazon ECS on EC2
* Amazon EKS

## Decision Outcome

Chosen option: "Amazon EKS", because Argo Rollouts and
Kyverno give us canaries and signed-only admission, and the
same manifests run on kind for every developer.

### Consequences

* Good, because one API for deploys, scaling and policy.
* Bad, because the control plane costs $0.10 an hour.
* Bad, because a Kubernetes upgrade is due every 14 months.

### Confirmation

The migration (M20-B01) moves traffic with zero failed
requests, and the canary rolls back by itself in a drill.

## Pros and Cons of the Options

### Stay on VMs with Ansible

* Good, because it works today: 6,103 requests, 0 failed.
* Bad, because canaries and admission are ours to build.

### Amazon ECS on EC2

* Good, because there is no extra charge for orchestration.
* Good, because it has built-in canary deploys (2025-10).
* Bad, because no Argo Rollouts and no Kyverno admission.

## More Information

Revisit if the teams shrink back to one. Course: M11-B01,
M12-B01, M15-B01, M18-B01.
