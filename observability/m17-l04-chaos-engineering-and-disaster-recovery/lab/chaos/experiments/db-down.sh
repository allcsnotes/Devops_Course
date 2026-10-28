# Stop the database: the course list should degrade (stale copy), enrollments will fail
HYPOTHESIS="with the database down, the course list still answers and errors stay under 0.1%"
DURATION=30
inject()   { docker compose -f ../compose.yaml stop db; }
rollback() { docker compose -f ../compose.yaml start db; }
