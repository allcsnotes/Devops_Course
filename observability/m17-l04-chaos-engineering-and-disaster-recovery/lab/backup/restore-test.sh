#!/usr/bin/env bash
# restore-test.sh: restore the newest dump into an EMPTY PostgreSQL (db-test) and prove the data is there
set -euo pipefail
source ~/bin/backup.env
F=$(ls -t /backups/*.dump | head -1)
echo "$(date +%T) restoring $F into db-test"
T0=$(date +%s.%N)
PGOPTIONS="-c client_min_messages=warning" psql -h db-test -d postgres -qc "DROP DATABASE IF EXISTS catalog" -c "CREATE DATABASE catalog"
pg_restore -h db-test -d catalog --no-owner "$F"
T1=$(date +%s.%N)
read -r N MAXT <<< "$(psql -h db-test -Atc "SELECT count(*), max(created_at) FROM enrollments" -F " ")"
LIVE=$(psql -h db -Atc "SELECT count(*) FROM enrollments WHERE created_at <= '$MAXT'")
echo "restored: $N enrollments, $(psql -h db-test -Atc 'SELECT count(*) FROM courses') courses, newest row $MAXT"
echo "live db, rows up to that moment: $LIVE"
[[ $N == "$LIVE" ]] && echo "RESTORE TEST PASSED in $(awk -v a=$T0 -v b=$T1 'BEGIN{printf "%.1f", b-a}') s" || { echo "RESTORE TEST FAILED"; exit 1; }
