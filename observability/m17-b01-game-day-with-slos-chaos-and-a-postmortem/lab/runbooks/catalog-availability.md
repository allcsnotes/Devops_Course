# Runbook: course list failing (ErrorBudgetBurn, slo=catalog-availability)

Severity: SEV2 if the page fires (course list failing for many students). Declare, name IC, ops, comms (lesson 2).

1. Did something change? `tail -3 incident/deploys.log`
   A deploy in the last hour: roll back first, debug later: `./deploy.sh <previous version> <you>`
2. Which route fails, which answer? The board: "Requests per second at the students, by answer".
3. Is the API itself stuck? The board: "API worker threads busy (of 8)". All 8 busy = requests are waiting on something.
4. Is it the database? `docker compose exec db psql -U allcs -d catalog -c "SELECT ... FROM pg_stat_activity"` (blockers)
5. Is it a dependency? Course Copilot: see runbooks/copilot-availability.md. The course list must never wait on it.

## Ticket: CatalogServingStale
The API answers from its stale copy because the database doesn't answer within 100 ms. Usually a lock:
find the blocking session with `pg_blocking_pids`, ask its owner, and end it with `pg_terminate_backend(pid)`.
