# Postmortem: a slow dependency took down the course list (game day, scenarios 2 and 3)

Game day in the staging lab, 21 October 2026, faults staged on purpose (fake data, simulated students, scripted people,
real system and real timestamps). Status: final · Severity: SEV2 · IC: Asha · Ops: Priya · Comms + scribe: Meera
Game master: Rahul · Author: Priya · Blameless: this document describes systems and decisions, not people's faults.

## Summary
Two sealed scenarios failed their hypotheses. A migration that locked the courses table (2) and a hung Course Copilot (3)
should have hurt nothing or only Copilot. Instead the course list failed for up to 2 min 21 s. In both, a slow dependency
held the API's time, requests timed out at nginx, and nginx marked both replicas dead. catalog-api 1.2 and an nginx change
fixed it; the same scenarios, re-run, held.

## Impact (timeline.py, from every simulated request)
| scenario            | course lists failed | budget used | slow lists | questions failed | budget used |
|---------------------|---------------------|-------------|------------|------------------|-------------|
| 2 migration lock    | 799 in 1 min 08 s   | 1.71 %      | 894        | 81               | 0.16 %      |
| 3 Copilot hangs     | 2,511 in 2 min 21 s | 5.38 %      | 9          | 745              | 1.44 %      |
Course-list budget used by the whole game day: 7.70 % of the 30-day budget (the game-day cap is 10 %).

## Timeline, scenario 3 (T = fault injected, 23:45:05 IST)
| time     | T     | what happened                                                        |
|----------|-------|----------------------------------------------------------------------|
| 23:45:05 | +0:00 | Copilot paused by the game master; questions start to hang           |
| 23:45:09 | +0:05 | first failed course list                                             |
| 23:46:35 | +1:31 | page #3, catalog-availability, 215x burn; acknowledged 23 s later     |
| 23:47:08 | +2:03 | SEV2 declared, roles named; status page: investigating                 |
| 23:47:10 | +2:06 | page #4, copilot-availability (never acknowledged: escalated at +4:06) |
| 23:47:28 | +2:23 | probe: Copilot timed out after 2 s; kill switch approved               |
| 23:47:29 | +2:24 | ./flag.sh ask off                                                      |
| 23:47:30 | +2:26 | last failed course list                                                |
| 23:48:09 | +3:04 | mitigated; status page: course list operational, Copilot major outage  |
| 23:51:17 | +6:12 | Copilot healthy again, ask back on                                     |
Scenario 2: ticket at +1:13, triaged SEV3 from its text; lock found and ended at +1:45; page at +2:08, after the fix.

## Contributing factors (how, not who)
1. nginx `max_fails=1` with `proxy_next_upstream error timeout`: one 2-second timeout marked a replica dead for 5 s.
   In scenario 3, 47 timed-out questions caused 2,797 "no live upstreams" answers; in scenario 2, 287 and 835.
2. The API waited up to 10 s for Copilot, with no limit on how many workers could wait.
3. One database connection per replica, behind a lock: under a lock every course list held it for up to 100 ms, so a
   queue formed (9 lists a second x 100 ms = 90 % busy). Lesson 4's "fail fast" alone could not help.
4. The stale-copy ticket arrived before the page, and its text ("database not answering in time") set SEV3 while
   errors reached 64 %. Severity was set from an alert's description, not from the SLIs.
5. During scenario 3 the note blamed busy workers; the numbers showed 1 and 2 busy. The mitigation was right anyway.
6. Two pages for one incident: the second was never acknowledged and escalated.

## What went well
- Every page fired within 2 min 08 s; the first page in scenario 3 was acknowledged in 23 s.
- The kill switch from the runbook ended course-list impact 1 second after it was flipped.
- Rollback first in scenario 1: 10 seconds, 0.59 % of the budget.

## Action items
| # | action                                                                      | type     | owner | due        | status |
|---|-----------------------------------------------------------------------------|----------|-------|------------|--------|
| 1 | Circuit breaker + bulkhead for the database and for Copilot, 0.5 s timeout  | fix      | Priya | 2026-10-21 | done, catalog-api 1.2; re-run held |
| 2 | nginx: questions in their own location, `proxy_next_upstream error` only    | fix      | Priya | 2026-10-21 | done; re-run held |
| 3 | Triage rule in every runbook: read the SLIs on the board before the severity | process  | Asha  | 2026-10-28 | open |
| 4 | Pager: group pages of one incident, or auto-ack the second for the IC        | detect   | Asha  | 2026-11-04 | open |
| 5 | Migrations: `lock_timeout` and off-peak runs; backfills outside the ALTER    | prevent  | Priya | 2026-11-04 | open |
| 6 | A connection pool instead of one connection per replica                      | prevent  | Priya | 2026-11-11 | open |
| 7 | k6 gate (lesson 3) with Copilot slowed, so the cascade can't return          | prevent  | Rahul | 2026-11-11 | open |
| 8 | Next game day in four weeks: repeat 2 and 3, add a replica loss under load    | learn    | Rahul | 2026-11-18 | open |

## Re-run after the fix (same sealed scenarios, same hypotheses)
- Scenario 2: 0 failed and 0 slow course lists, stale copy served 18 a second, ticket at +1:13, no page. Held.
- Scenario 3: 0 failed course lists; Copilot breakers open, questions fail fast with 503; Copilot page at +2:06;
  373 failed questions, 0.72 % of the Copilot budget. Held.
