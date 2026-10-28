# Error budget policy: catalog API

SLO:      99.9 % of GET /api/courses succeed (not 5xx), rolling 30 days
Budget:   0.1 % of requests, about 26,000 a month at 10 a second
Owner:    platform team (Asha). Agreed by: product, developers (Priya), SRE (Rahul)

## What happens

- More than 25 % left:  ship as usual, behind canaries and feature flags
- 25 % or less left:    risky releases need a rollback plan; reliability work first
- Budget spent:         freeze feature releases; only P0 bug fixes and security
                        fixes until the SLO is met again over 30 days
- One incident burns more than 20 % of the budget: a postmortem, with at least
  one action item

This policy is not a punishment. Disputes go to the engineering lead.
