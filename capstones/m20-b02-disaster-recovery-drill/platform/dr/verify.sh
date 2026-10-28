#!/usr/bin/env bash
# dr/verify.sh: what "restored" means for allcsvideos. Every check prints PASS or FAIL.
set -uo pipefail
export PGPASSWORD=$(cat ~/break-glass/db-admin-password); F=0
check(){ if eval "$2" >/dev/null 2>&1; then echo "PASS  $1"; else echo "FAIL  $1"; F=1; fi; }
SITE=http://10.0.202.30:30080
echo "data:    $(psql -h 10.0.202.10 -U postgres -d catalog -Atc "select count(*) || ' enrollments, newest ' || to_char(max(created_at), 'HH24:MI:SS') from enrollments")"
check "browse: the course list answers 200" "[[ \$(curl -s -o /dev/null -w '%{http_code}' $SITE/api/courses) == 200 ]]"
E=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"student":"drill@example.com","course_id":1}' $SITE/api/enroll)
echo "enroll:  $E"
check "enroll: a real enrollment is saved" "psql -h 10.0.202.10 -U postgres -d catalog -Atc \"select 1 from enrollments where id = $(jq -r .enrollment <<<"$E" 2>/dev/null || echo 0)\" | grep -qx 1"
check "secrets: catalog-db synced from Vault" "kubectl get externalsecret catalog-db -n allcs -o jsonpath='{.status.conditions[0].status}' | grep -qx True"
check "secrets: Vault unsealed, catalog/db readable" "VAULT_TOKEN=\$(jq -r .root_token ~/break-glass/vault-init.json) vault kv get -mount=allcs catalog/db"
check "dashboards: Grafana has the production board" "curl -sf 'http://10.0.202.14:3000/api/search?query=production' | jq -e 'length == 1'"
check "backups: the new primary archives WAL to the bucket" "psql -h 10.0.202.10 -U postgres -d catalog -Atc 'select archived_count > 0 and failed_count = 0 from pg_stat_archiver' | grep -qx t"
exit $F
