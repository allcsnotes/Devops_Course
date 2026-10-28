# SEALED (game master only). Scenario 2: a schema migration holds a lock on the courses table
HYPOTHESIS="a migration locks the courses table: the course list keeps both SLOs from its stale copy, nobody is paged, a ticket arrives within 3 minutes, and ops ends the lock within 10"
SQL="BEGIN; ALTER TABLE courses ADD COLUMN level text; SELECT pg_sleep(900); COMMIT;"   # pg_sleep stands in for a slow backfill
inject()   { docker compose -f ../compose.yaml exec -d -e PGAPPNAME=migrate-42 db psql -U allcs -d catalog -c "$SQL"
             echo "migration migrate-42 started: ALTER TABLE courses, then a long backfill"; }
rollback() { docker compose -f ../compose.yaml exec -T db psql -U allcs -d catalog -Atc \
               "SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE application_name = 'migrate-42'" |
               sed 's/^0$/nothing to do: the migration was already ended/; s/^[1-9].*/migration ended by the game master/'; }
