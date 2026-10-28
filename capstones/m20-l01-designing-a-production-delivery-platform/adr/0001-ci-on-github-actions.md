---
status: accepted
date: 2026-10-22
decision-makers: Asha, Rahul
consulted: Priya
informed: Meera
---

# Build and test every change in GitHub Actions

## Context and Problem Statement

Every change to allcsvideos must be built once, tested and
scanned before it can merge. Which CI system runs that work?

## Decision Drivers

* The code already lives on GitHub (pull requests, reviews).
* Two platform engineers: no time to run CI servers.
* Cloud access without long-lived keys (OIDC).

## Considered Options

* GitHub Actions
* GitLab CI
* Jenkins

## Decision Outcome

Chosen option: "GitHub Actions", because it sits next to the
code and the reviews, needs no servers for us to run, and
supports OIDC to AWS.

### Consequences

* Good, because pipelines are YAML in the same repository.
* Bad, because the workflow syntax ties us to GitHub.

### Confirmation

Branch protection requires the lint, unit, integration and
security checks on every pull request.

## Pros and Cons of the Options

### GitLab CI

* Good, because code, CI and registry come in one product.
* Bad, because our code and reviews are on GitHub.

### Jenkins

* Good, because it runs anywhere, with many plugins.
* Bad, because we would run, patch and back up the server.

## More Information

Revisit if the code moves off GitHub. Course: M08, M09-L05.
