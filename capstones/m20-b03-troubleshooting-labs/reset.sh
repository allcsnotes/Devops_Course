#!/bin/bash
# reset.sh <1-10|all>: put the lab back to healthy for one scenario (or all of them), then show the status.
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd); P=${P:-trouble}; APP_PW=${APP_PW:-k8Hq2Zx7Vt4Lm9Pw3Rb6}
ops(){ docker exec -i -e TZ=UTC -u asha -w /home/asha $P-ops "$@"; }
on(){ local c=$1; shift; docker exec -i $P-$c "$@"; }
k(){ ops kubectl -n allcs "$@"; }
r(){ case $1 in
  1) local s=$(on ns1 dig +short SOA allcsvideos.test @127.0.0.1 | awk '{print $3}')
     docker cp $H/server/files/db.allcsvideos.test $P-ns1:/etc/bind/zones/db.allcsvideos.test
     on ns1 sh -c "chmod 644 /etc/bind/zones/db.allcsvideos.test && sed -i 's/2026102201  ; serial/$((s + 1))  ; serial/' /etc/bind/zones/db.allcsvideos.test && rndc reload allcsvideos.test >/dev/null" ;;
  2) on web01 rm -f /var/log/allcs/api-debug.log ;;
  3) on web01 sh -c 'renew-cert 90 >/dev/null && systemctl reload nginx' ;;
  4) ops kubectl apply -f manifests/20-thumbs.yaml >/dev/null ;;
  5|8|10) ops kubectl apply -f manifests/10-catalog.yaml >/dev/null; k delete configmap catalog-config-v2 --ignore-not-found >/dev/null ;;
  6) on db psql -q -U postgres -c "ALTER ROLE allcs_app PASSWORD '$APP_PW'"
     on web01 sh -c "sed -i 's/^DB_PASSWORD=.*/DB_PASSWORD=$APP_PW/' /etc/allcs/api.env && systemctl restart allcs-api"
     ops sh -c 'cd allcsvideos-ops && git reset -q --hard $(git rev-list --max-parents=0 HEAD) && rm -f .git/hooks/pre-commit && git reflog expire --expire=now --all && git gc -q --prune=now' ;;
  7) ops kubectl apply -f manifests/10-catalog.yaml >/dev/null ;;
  9) on web01 systemctl stop allcs-report
     on db psql -q -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name='nightly-report'" >/dev/null ;;
  *) echo "usage: reset.sh <1-10|all>"; exit 1 ;;
esac; ops sh -c "echo \"\$(date +%H:%M:%S) RESET $1\" >> ~/incident/lab.log"; }
if [[ ${1:-} == all ]]; then for i in {1..10}; do r $i; done; else r ${1:?usage: reset.sh <1-10|all>}; fi
k rollout status deploy/catalog --timeout=120s >/dev/null 2>&1 || true
bash "$H/lab.sh" status
