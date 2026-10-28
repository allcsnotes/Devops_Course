#!/usr/bin/env bash
# dr-restore.sh: the runbook, automated. Rebuild the catalog database from the newest backup.
set -euo pipefail
cd "$(dirname "$0")/.."
on_backup() { docker compose exec -T backup bash -c "source ~/bin/backup.env; $1"; }
echo "$(date +%T) 1. start an empty PostgreSQL"
docker compose up -d --wait db 2>&1 | tail -1
echo "$(date +%T) 2. restore the newest dump beside it, into catalog_new"
on_backup 'F=$(ls -t /backups/*.dump | head -1); echo "   $F"; createdb catalog_new; pg_restore -d catalog_new --no-owner "$F"'
echo "$(date +%T) 3. check it before anyone uses it"
on_backup 'psql -d catalog_new -Atc "SELECT count(*) || '"' enrollments, newest '"' || max(created_at) FROM enrollments" | sed "s/^/   /"'
echo "$(date +%T) 4. switch: the restored database becomes catalog"
on_backup 'psql -d postgres -qc "DROP DATABASE catalog WITH (FORCE)" -c "ALTER DATABASE catalog_new RENAME TO catalog"'
echo "$(date +%T) 5. smoke test through the load balancer"
curl -s -X POST -H 'Content-Type: application/json' -d '{"student":"drill@example.com","course_id":1}' localhost:8080/api/enroll | sed 's/^/   /'
echo "$(date +%T) done"
