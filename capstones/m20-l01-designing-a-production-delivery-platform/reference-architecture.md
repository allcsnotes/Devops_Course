# allcsvideos delivery platform: reference architecture

Version 1, 2026-10-22. Owners: Asha, Rahul. One page, on purpose.

## Requirements (they decide everything below)

| Driver      | allcsvideos today                                   |
|-------------|-----------------------------------------------------|
| Users       | students worldwide, all day (Lukas in Frankfurt)    |
| SLO         | course list: 99.9% success over 30 days, p99 250 ms |
| Team        | 3 product teams, 2 platform engineers               |
| Compliance  | card payments by a provider; no card data stored    |
| Budget      | sandbox labs destroyed the same day; tags on all    |
| RTO / RPO   | 1 hour / 5 minutes for the database (drill: 46 s / 62 s) |

## Layers: decision, alternative, switch when

| Layer          | Decision (ADR)                 | Alternative          | Choose it when                         |
|----------------|--------------------------------|----------------------|----------------------------------------|
| Source         | trunk-based, PR review, CODEOWNERS | GitFlow          | you ship boxed releases on a schedule  |
| CI             | GitHub Actions (0001)          | GitLab CI, Jenkins   | code on GitLab; on-prem, plugin needs  |
| Artifacts      | build once, SBOM, cosign, digest | rebuild per env    | never                                  |
| Infrastructure | Terraform (0004), dev/staging/prod accounts | OpenTofu, Pulumi; one account | license policy; one team |
| Runtime        | EKS (0002)                     | ECS on EC2, VMs      | one team, no canary or admission needs |
| Delivery       | Argo CD + Argo Rollouts canary (0003) | Flux, CI push | CLI-first team; very small setup     |
| Secrets        | Vault or Secrets Manager + ESO | CI secrets only      | no cluster yet                         |
| Observability  | Prometheus, Loki, Tempo, one Grafana | managed services | nobody can run the storage           |
| Reliability    | SLO burn alerts, PITR, game days | backups only       | never skip the restore test            |
| Security       | least privilege, Kyverno, signed-only | manual review  | never                                 |
| Cost           | default tags, budgets, rightsizing | monthly bill review | very small, flat spend             |
| Platform       | golden path template, Backstage | a wiki page + one template | fewer than ~3 teams          |

## Scorecard

The five DORA metrics (dora.dev, checked 2026-10-22): change lead time,
deployment frequency, failed deployment recovery time, change fail rate,
deployment rework rate. Compare each team with its own past.
