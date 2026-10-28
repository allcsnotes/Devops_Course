# API release path: reference architecture

Version 1, 2026-10-22. Owner: Asha. Decision record: ADR 0007.

## Requirements

| Driver | Value |
|---|---|
| SLO | course list: 99.9% of requests succeed over 30 days; p99 under 250 ms |
| Blast radius | a bad release reaches at most 10% of requests |
| Detection | the release decides by itself within 5 minutes of exposure |
| Rollback | automatic, all traffic back on the stable version within 5 minutes |
| Team | 3 product teams ship; 2 platform engineers own the path |

## The path, from commit to users

```text
  Priya's pull request
        |  CI: lint, test, scan, build once, sign, push by digest
        v
  registry: api@sha256:...  ------------------------------+
        |                                                 |
  pull request to the GitOps repo: image digest bump      |
        |  reviewed, merged                               |
        v                                                 |
  Argo CD (in the cluster) syncs the Rollout object       |
        |                                                 |
        v                                                 |
  Argo Rollouts controller                                |
        |  step 1: 10% of pods new  -> analysis (5 min)   |
        |  step 2: 25%              -> analysis (5 min)   |
        |  step 3: 50%              -> analysis (5 min)   |
        |  step 4: 100%, old ReplicaSet scaled down       |
        |                                                 |
        |  analysis = Prometheus queries on the canary:   |
        |   5xx ratio, p99 latency, request count         |
        |  fail -> abort -> 100% back to stable  <--------+
        v
  students (Lukas in Frankfurt) through the Gateway and the Service
```

## Components and owners

| Component | Runs where | Owner | Notes |
|---|---|---|---|
| CI pipeline | GitHub Actions | platform | builds once; promotes the same digest |
| GitOps repo | Git | each product team | one folder per environment, reviewed PRs |
| Argo CD | each cluster | platform | pulls; CI holds no cluster credentials |
| Argo Rollouts | each cluster | platform | replaces the API Deployment with a Rollout |
| Prometheus | each cluster | platform | canary pods labelled `rollouts-pod-template-hash`, so queries split stable from canary |
| Burn-rate alerts | Alertmanager | on-call | still page if a release slips through the gate |

## Trade-offs we accept

* Replica-based weights: with 4 replicas, 10% is really "1 of 4 pods" (25%). Until a traffic router is added, run at least 10 replicas during a release, or accept the coarser step.
* The analysis needs traffic: below 50 requests in a step window the result is "inconclusive" and the rollout pauses for a person.
* Database migrations run before the rollout and must be backward compatible; the canary never rolls back a schema.
