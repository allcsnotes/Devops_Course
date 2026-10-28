# Runbook: Course Copilot failing (ErrorBudgetBurn, slo=copilot-availability)

Course Copilot belongs to the Copilot team: page their on-call, don't restart their service yourself.
1. Is it answering? `./probe.sh http://copilot:8000/healthz` (2 second limit)
2. Is it hurting the rest of the site? Check the course list on the board.
3. Kill switch: `./flag.sh ask off` stops all Copilot calls; students see "Copilot is switched off".
   Switch it back on when the Copilot team says it's healthy: `./flag.sh ask on`
