# Postmortem: course list failing after catalog-api 1.5.0

Lab incident, staged on purpose in the M17-L02 lab (fake data, scripted people, real system and real timestamps).
Status: final · Severity: SEV2 · Incident commander: Asha · Ops lead: Rahul · Comms lead: Priya · Author: Rahul
Date: 2026-10-21 (all times IST) · Blameless: this document describes systems and decisions, not people's faults.

## Summary
Release 1.5.0 of catalog-api added a "trending this week" count to the course list. The new query read all
2,000,000 enrollments on every request. Under normal traffic it hit the 1 second statement timeout, and the course
list failed for most students for 2 min 15 s. We rolled back to 1.4.2, and the errors stopped.

## Impact
- 21:18:00 to 21:20:15, 2 min 15 s of user impact.
- 890 of 1,355 requests failed (65.7%): the course list 878 of 934 (94.0%), course pages 12 of 421 (2.9%).
- Video playback and checkout were not affected.
- Error budget: 890 of the 129,600 failures allowed in 30 days (SLO 99.5% at 10 requests a second), 0.69%.

## Timeline (from timeline.py r2: load CSV, deploy log, pager, status page, incident log)
| time | T | what happened |
|------|---|---------------|
| 21:17:59 | -00:02 | catalog-api 1.5.0 rollout started (Priya) |
| 21:18:00 | +00:00 | first failed request: impact starts |
| 21:19:23 | +01:23 | CatalogErrorBudgetBurn fired, Asha paged (primary) |
| 21:19:50 | +01:50 | Asha acknowledged |
| 21:19:57 | +01:56 | SEV2 declared; roles: IC Asha, ops Rahul, comms Priya |
| 21:20:05 | +02:05 | status page: investigating, course catalog partial outage |
| 21:20:13 | +02:12 | Rahul: errors began with 1.5.0, statement timeouts; proposes rollback. Asha approves |
| 21:20:15 | +02:15 | last failed request: impact ends |
| 21:20:20 | +02:19 | rollback to 1.4.2 finished |
| 21:21:01 | +03:01 | status page: monitoring |
| 21:21:23 | +03:23 | alert resolved |
| 21:21:54 | +03:54 | status page: resolved; incident closed |

Time to detect 1 min 23 s · time to acknowledge 27 s · time to restore 2 min 15 s.

## Root cause and contributing factors
Trigger: the 1.5.0 trending query, `SELECT course_id, count(*) FROM enrollments WHERE enrolled_at > now() - interval
'7 days' GROUP BY course_id`, ran a parallel sequential scan of the whole table (329 ms alone, more under load).
There is no single root cause. These conditions together turned one slow query into an outage:
1. No index on `enrollments.enrolled_at`. With one, the same query takes 27 ms (EXPLAIN ANALYZE, captured).
2. The query runs on every course list request, not once a minute from a cache.
3. The release went to 100% of traffic at once: one container, replaced in place, no canary (module 9).
4. The health check only says the process is up: `/healthz` answered `ok` while 94% of course list requests failed.
5. Nothing measured the new query against production-sized data before release.

## What went well
- The SLO burn-rate alert paged the primary on-call 83 seconds after the first failure.
- One person decided (the IC), one person changed production (the ops lead), one person talked to users (comms).
- Rollback first: one command, 7 seconds, before the cause was fully understood.

## What went badly / where we got lucky
- 1 min 23 s of failures before anyone knew; the lab windows are short, production windows (1 h / 5 m) are slower.
- We got lucky that course pages used a different query: only 2.9% of them failed.

## Action items
| # | action | type | owner | due |
|---|--------|------|-------|-----|
| 1 | Add index `enrollments (enrolled_at)` with CREATE INDEX CONCURRENTLY, before re-releasing 1.5.0 | fix | Priya | 2026-10-23 |
| 2 | Cache the trending counts (refresh every 5 min) instead of computing per request | fix | Priya | 2026-10-30 |
| 3 | Canary releases for catalog-api: 5% of traffic, auto-rollback on burn rate | prevent | Rahul | 2026-11-06 |
| 4 | Readiness check that runs the course list query, not just "process up" | detect | Asha | 2026-10-30 |
| 5 | Load test new queries on a production-sized copy before release (M17-L03) | prevent | Rahul | 2026-11-13 |
| 6 | Runbook: "catalog errors after a deploy -> roll back first" in runbooks/catalog-api.md | mitigate | Asha | 2026-10-23 |
