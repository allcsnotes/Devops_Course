#!/usr/bin/env bash
# dr/restore-test.sh: prove the backups restore. A throwaway PostgreSQL restores the newest base backup + archived WAL
# from the bucket (the same image and entrypoint the real restore uses), then we compare it with the live database.
# It runs WITHOUT archive_mode: a test restore must never write WAL or timeline files into the production bucket.
set -euo pipefail
export PGPASSWORD=$(cat ~/break-glass/db-admin-password); T=dr-restore-test; IP=10.0.202.20
T0=$(date +%s.%N)
docker run -d --rm --label course=devops --name $T --network dr-net --ip $IP -e DB_SOURCE=pitr \
  -e BUCKET=http://10.0.202.6:9000 -e POSTGRES_PASSWORD=unused localhost:5001/allcs/postgres:18.6-wal \
  postgres -c timezone=UTC >/dev/null
until [[ $(psql -h $IP -U postgres -d catalog -Atc "select pg_is_in_recovery()" 2>/dev/null) == f ]]; do sleep 1; done
T1=$(date +%s.%N)
read -r N MAXID NEWEST <<<"$(psql -h $IP -U postgres -d catalog -At -F ' ' -c "select count(*), max(id), to_char(max(created_at), 'YYYY-MM-DD_HH24:MI:SS') from enrollments")"
LIVE=$(psql -h 10.0.202.10 -U postgres -d catalog -Atc "select count(*) from enrollments where id <= $MAXID")
docker logs $T 2>&1 | grep -E 'dr-entrypoint: restoring|restored log file' | sed -n '1p;$p' | cut -c1-90
echo "restored: $N enrollments, newest row ${NEWEST/_/ }"
echo "live:     $LIVE enrollments up to that moment"
docker rm -f -v $T >/dev/null
[[ $N == "$LIVE" ]] && echo "RESTORE TEST PASSED in $(awk -v a=$T0 -v b=$T1 'BEGIN{printf "%.0f", b-a}') s" || { echo "RESTORE TEST FAILED"; exit 1; }
