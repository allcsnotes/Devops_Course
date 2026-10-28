---
status: proposed
date: 2026-10-22
decision-makers: Asha, Rahul
consulted: Priya
informed: Meera, support
---

# Release the API with automated canaries, gated on the SLO

## Context and Problem Statement

The API runs on Kubernetes as a Deployment with a default rolling update.
In the last quarter two releases broke the course list for every student
before anyone noticed, and each rollback was a manual `kubectl rollout undo`
after a page. How should a new API version reach users so that a bad
release hurts few users, for a short time, without a person watching?

## Decision Drivers

* Limit the blast radius: a bad release should reach at most a small share of requests.
* Decide from the user's view: the SLI the SLO uses (5xx ratio and p99 latency), not CPU.
* Roll back automatically, in minutes, without cluster credentials in CI.
* Fit what the team already runs: GitOps with Argo CD, Prometheus, one cluster per environment.
* Database changes must stay backward compatible (expand, migrate, contract), whatever the strategy.

## Considered Options

* Keep the rolling update, add readiness probes and a manual post-deploy check
* Blue-green: a full second Deployment and a Service switch
* Canary with Argo Rollouts and Prometheus analysis

## Decision Outcome

Chosen option: "Canary with Argo Rollouts and Prometheus analysis", because it
is the only option that sends a small, growing share of real traffic to the new
version and stops on its own when the SLI degrades, and it plugs into Argo CD,
which already applies every change from Git.

### Consequences

* Good, because a bad release reaches 10% of requests for a few minutes, then rolls back by itself.
* Good, because the gate uses the same SLI as the SLO and its burn-rate alerts.
* Bad, because the team must run and upgrade one more controller (Argo Rollouts).
* Bad, because low-traffic hours give the analysis few requests: the gate needs a minimum request count.
* Neutral, because old and new versions serve at the same time, so APIs and schemas must stay compatible (already a rule).

### Confirmation

Before this ADR is accepted, a staging drill must show: a release with an injected
10% error rate is aborted by the analysis and fully rolled back within 5 minutes,
with at most 10% of staging requests exposed; and a healthy release reaches 100%
with no manual step. Results go into the rollout plan's review.

## Pros and Cons of the Options

### Keep the rolling update, add readiness probes and a manual post-deploy check

* Good, because nothing new to run; readiness probes alone stopped failed requests during rollouts in the course lab (M13-L04).
* Bad, because every new pod gets real traffic as soon as it is ready: a bad version reaches all users within one rollout.
* Bad, because the check and the rollback depend on a person.

### Blue-green: a full second Deployment and a Service switch

* Good, because the switch and the switch back are one change each.
* Good, because the new version can be tested with production config before any user sees it.
* Bad, because it needs twice the capacity during a release.
* Bad, because after the switch 100% of users are on the new version at once.

### Canary with Argo Rollouts and Prometheus analysis

* Good, because exposure grows in steps (10%, 25%, 50%, 100%) with an analysis between steps.
* Good, because aborting returns all traffic to the stable ReplicaSet.
* Bad, because traffic-share precision depends on replica counts unless a traffic router (Gateway API or a mesh) is added.

## More Information

Related: the SLO and burn-rate alerts (M17-L01), deployment strategies (M09-L02),
GitOps (M15-L03). Revisit if traffic grows enough to justify header-based routing
for staff-first canaries.
