#!/bin/bash
# break.sh <1-10>: inject ONE real fault into the lab (staged on purpose). Prints what it did, without the answer
# being needed to play: the scenario cards in scenarios.md say what to look for. Undo with reset.sh <n> (or all).
set -euo pipefail
P=${P:-trouble}; NET=10.0.203; n=${1:?usage: break.sh <1-10>}
ops(){ docker exec -i -e TZ=UTC -u asha -w /home/asha $P-ops "$@"; }
on(){ local c=$1; shift; docker exec -i $P-$c "$@"; }
k(){ ops kubectl -n allcs "$@"; }
log(){ ops sh -c "echo \"\$(date +%H:%M:%S) BREAK $n: $1\" >> ~/incident/lab.log"; echo "break $n: $1"; }
case $n in
  1) # the db-01 record now points at the OLD database server's address (nothing answers there)
     on ns1 sed -i -e "s/^db-01 .*/db-01       IN A      $NET.21/" -e 's/2026102201  ; serial/2026102202  ; serial/' /etc/bind/zones/db.allcsvideos.test
     on ns1 rndc reload allcsvideos.test >/dev/null; log "a DNS record changed" ;;
  2) # a forgotten debug log grows until the 64 MB log disk is full
     on web01 su -s /bin/sh www-data -c 'yes "$(date +%FT%T) DEBUG request dump: headers={...} body={...} trace=on" > /var/log/allcs/api-debug.log 2>/dev/null; true'
     # users keep browsing: 100 requests, so the access log needs a new block on the full disk
     on web01 sh -c 'for i in $(seq 100); do curl -s -o /dev/null http://127.0.0.1:8080/healthz; done'
     log "debug logging was left on" ;;
  3) # the certificate renewal never ran: the live certificate expired an hour ago
     on web01 sh -c 'LAB_NOT_BEFORE=$(date -u -d "90 days ago" +%Y%m%d%H%M%SZ) LAB_NOT_AFTER=$(date -u -d "1 hour ago" +%Y%m%d%H%M%SZ) renew-cert >/dev/null'
     on web01 systemctl reload nginx; log "the certificate renewal job did not run" ;;
  4) # thumbs "right-sized" to 48 MiB from an average-usage dashboard; it needs more at start
     k set resources deploy/thumbs --requests=memory=32Mi --limits=memory=48Mi >/dev/null; log "thumbs memory settings changed" ;;
  5) # a release renamed the liveness path in the manifest: /health instead of /healthz
     k patch deploy/catalog --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/path","value":"/health"}]' >/dev/null
     log "catalog release with new probe settings" ;;
  6) # Priya commits the web-01 env file (with the database password) to fix a deploy quickly
     on web01 cat /etc/allcs/api.env | ops sh -c 'mkdir -p allcsvideos-ops/deploy/web-01 && cat > allcsvideos-ops/deploy/web-01/api.env'
     ops sh -c 'cd allcsvideos-ops && git add deploy && git -c user.name=Priya -c user.email=priya@example.com commit -qm "deploy: web-01 env for the hotfix"'
     log "a commit was pushed to allcsvideos-ops" ;;
  7) # a chart refactor renamed the Service selector; the pods keep their old label
     k patch svc catalog -p '{"spec":{"selector":{"app":"catalog-api"}}}' >/dev/null; log "catalog Service updated" ;;
  8) # the release points at a tag that was never built or pushed
     k set image deploy/catalog api=trouble-api:1.0.1 >/dev/null; log "catalog release 1.0.1 deployed" ;;
  9) # the nightly report job leaks database connections
     on web01 systemctl start allcs-report; log "the nightly report job started" ;;
  10) # a new config version with a typo: capital letter O instead of a zero
     k create configmap catalog-config-v2 --from-literal=PAGE_SIZE=2O --from-literal=CACHE_MB=8 >/dev/null
     k patch deploy/catalog --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/envFrom/0/configMapRef/name","value":"catalog-config-v2"}]' >/dev/null
     log "catalog config v2 rolled out" ;;
  *) echo "usage: break.sh <1-10>"; exit 1 ;;
esac
