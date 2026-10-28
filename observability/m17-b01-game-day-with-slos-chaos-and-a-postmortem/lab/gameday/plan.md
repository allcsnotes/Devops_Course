# Game day plan: allcsvideos, 21 October 2026

Goal: prove that our SLOs, alerts, runbooks and incident process work, by running real failures on purpose.
Where: the staging lab (Docker Compose project gameday-lab). Never production. Students are simulated (20/s).

## Roles
| role         | who   | does                                                                 |
|--------------|-------|----------------------------------------------------------------------|
| game master  | Rahul | picks and injects the faults (sealed), watches the abort lines        |
| incident commander | Asha | runs the response exactly as in a real incident (lesson 2)     |
| ops lead     | Priya | investigates and changes the system; the only one who does           |
| comms + scribe | Meera | status page updates, and the timeline with inc.sh                 |

## Rules of engagement
- Scope: the catalog API, the load balancer, Course Copilot and the catalog database in staging. Nothing else.
- The responders don't know the faults, their order or their timing. They use only the pager, the board,
  the runbooks and their terminals. Copilot is owned by "another team": route around it, don't fix it.
- Blast radius: one fault at a time, in staging, with simulated students. No real users, no real data.
- Abort conditions (gameday/gm.sh checks every 10 s and rolls back by itself):
  1. the game day has spent more than 10 % of any 30-day error budget (docs/error-budget-policy.md)
  2. a fault has run 8 minutes without mitigation
  3. anyone says "stop the exercise" (the game master creates gameday/STOP)
- Who is told: the whole team, support and product a day ahead; the status page is the lab one.
- Each scenario ends when the IC logs "mitigated"; then the game master removes the fault.

## Afterwards
Review each hypothesis against the measured numbers, write a blameless postmortem for every one that failed,
and add the action items to the backlog with owners and dates.
