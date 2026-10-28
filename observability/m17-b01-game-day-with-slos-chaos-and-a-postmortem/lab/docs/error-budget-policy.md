# Error budget policy: allcsvideos

| SLO                  | objective                          | 30-day budget at 20 requests/s |
|----------------------|------------------------------------|--------------------------------|
| catalog-availability | 99.9 % of course lists not 5xx      | 46,656 bad requests            |
| catalog-latency      | 99 % of course lists within 250 ms  | 466,560 slow requests          |
| copilot-availability | 99 % of Copilot answers not 5xx     | 51,840 bad requests            |

Owner: platform team (Asha). Agreed by: product, developers (Priya), SRE (Rahul), Copilot team.

## What happens

- More than 25 % left:  ship as usual, behind canaries and feature flags
- 25 % or less left:    risky releases need a rollback plan; reliability work first
- Budget spent:         freeze feature releases; only P0 bug fixes and security
                        fixes until the SLO is met again over 30 days
- One incident burns more than 20 % of a budget: a postmortem, with at least
  one action item
- A game day may spend at most 10 % of any budget: the game master aborts
  at that line (gameday/gm.sh checks it every 10 seconds)

This policy is not a punishment. Disputes go to the engineering lead.
