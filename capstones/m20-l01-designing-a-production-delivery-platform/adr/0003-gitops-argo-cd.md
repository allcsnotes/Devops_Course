---
status: accepted
date: 2026-10-22
decision-makers: Asha, Rahul
consulted: Priya
informed: Meera
---

# Deploy to the clusters with Argo CD (GitOps)

## Context and Problem Statement

CI builds and signs the images. How does a new version get
into the cluster, and how do we see and undo what changed?

## Decision Drivers

* Git is the record of what runs in each environment.
* CI must not hold credentials for production clusters.
* Drift (manual kubectl changes) is detected and reverted.

## Considered Options

* Argo CD
* Flux
* Push from CI with kubectl or helm

## Decision Outcome

Chosen option: "Argo CD", because it pulls from Git, heals
drift, shows every application in a web UI, and pairs with
Argo Rollouts for canaries.

### Consequences

* Good, because a rollback is a git revert.
* Bad, because Argo CD itself must be run and upgraded.

### Confirmation

Self-heal undoes a manual scale within seconds (M15-B01),
and no CI job holds a production kubeconfig.

## Pros and Cons of the Options

### Flux

* Good, because it is small and CLI-first.
* Neutral, because it has no built-in web UI.

### Push from CI with kubectl or helm

* Good, because it is the simplest to start with.
* Bad, because CI holds cluster credentials, and nothing
  reverts drift.

## More Information

Both Argo and Flux are CNCF graduated projects (2022).
