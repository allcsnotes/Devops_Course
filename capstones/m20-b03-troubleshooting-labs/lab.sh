#!/bin/bash
# Troubleshooting labs (M20-B03): a small allcsvideos stack with 10 real, injectable faults.
#   bash lab.sh up       build the images, start the servers and the kind cluster, deploy the healthy stack
#   bash lab.sh status   the user's view: one check per scenario (all should say ok after up / reset)
#   bash lab.sh ops      a shell on the ops workstation (asha@ops)
#   bash lab.sh sh NAME  a shell on web-01 or ns1 (asha@web-01, asha@ns1)
#   bash lab.sh down     remove everything this lab created (scoped to the prefix only)
#   bash lab.sh check    the four cleanup checks (must print nothing after down)
# Only the docker CLI runs on your machine. Everything else runs in containers named $P-* (label course=devops).
# Machine:   network $P-net 10.0.203.0/24
#   web-01  .10  Ubuntu 24.04 + systemd: nginx (TLS 443) -> allcs-api (python3, psycopg2); /var/log/allcs is a 64 MB disk
#   ns1     .53  Ubuntu 24.04 + systemd: BIND 9, authoritative for allcsvideos.test
#   db-01   .20  PostgreSQL 18.6, max_connections=20
#   ops     host network: kubectl, kind, curl, dig, openssl, psql, git, gitleaks (Asha's workstation)
#   kind cluster $P (one node): namespace allcs with catalog (2 pods + Service), thumbs, client
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd); P=${P:-trouble}; NET=10.0.203
NODE_IMAGE=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
PG_IMAGE=postgres:18.6-alpine3.24
# FAKE lab credentials (demo only, never real): the app role and the database superuser
APP_PW=${APP_PW:-k8Hq2Zx7Vt4Lm9Pw3Rb6}; SU_PW=${SU_PW:-lab-superuser-FAKE-pw}
LB=(--label course=devops)
SYSD=(--privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock)
ops(){ docker exec -i -e TZ=UTC -u asha -w /home/asha $P-ops "$@"; }
opsroot(){ docker exec -i -u 0 $P-ops "$@"; }
on(){ local c=$1; shift; docker exec -i $P-$c "$@"; }
boot(){ local i=0; until [[ $(docker exec $P-$1 systemctl is-system-running 2>/dev/null) =~ ^(running|degraded)$ ]] || (( i++ > 60 )); do sleep 1; done; }
apienv(){ printf 'DB_HOST=db-01.allcsvideos.test\nDB_NAME=allcs\nDB_USER=allcs_app\nDB_PASSWORD=%s\nLOG_FILE=/var/log/allcs/api.log\n' "$1"; }
up(){
  docker network inspect $P-net >/dev/null 2>&1 || docker network create "${LB[@]}" --subnet $NET.0/24 --gateway $NET.254 $P-net >/dev/null
  docker build -q -t $P-server:1.0 $H/server >/dev/null
  docker build -q -t $P-ops:1.0 $H/ops >/dev/null
  docker build -q -t $P-api:1.0 $H/k8s/app >/dev/null
  # db-01: PostgreSQL in memory (tmpfs), 20 connections max (3 reserved for superusers)
  docker run -d "${LB[@]}" --name $P-db --hostname db-01 --network $P-net --ip $NET.20 --memory 256m \
    -e POSTGRES_PASSWORD=$SU_PW -e POSTGRES_DB=allcs --tmpfs /var/lib/postgresql:size=128m \
    -v $H/db/init.sql:/docker-entrypoint-initdb.d/10-init.sql:ro $PG_IMAGE -c max_connections=20 >/dev/null
  # ns1 and web-01: systemd servers
  docker run -d "${LB[@]}" --name $P-ns1 --hostname ns1 --network $P-net --ip $NET.53 --memory 128m "${SYSD[@]}" $P-server:1.0 >/dev/null
  docker run -d "${LB[@]}" --name $P-web01 --hostname web-01 --network $P-net --ip $NET.10 --memory 384m "${SYSD[@]}" \
    --tmpfs /var/log/allcs:size=64m $P-server:1.0 >/dev/null
  boot ns1; boot web01
  on ns1 install -d -o root -g bind /etc/bind/zones
  for f in named.conf.options named.conf.local; do docker cp $H/server/files/$f $P-ns1:/etc/bind/$f; done
  docker cp $H/server/files/db.allcsvideos.test $P-ns1:/etc/bind/zones/db.allcsvideos.test
  on ns1 sh -c 'chown -R root:bind /etc/bind/zones && chmod 644 /etc/bind/zones/* && named-checkconf && systemctl enable --now named >/dev/null 2>&1'
  # web-01 asks ns1 for names (what DHCP / netplan would set on a real server); resolv.conf is a bind mount: rewrite in place
  on web01 sh -c 'printf "nameserver '$NET'.53\nsearch allcsvideos.test\n" > /etc/resolv.conf'
  on web01 install -d /opt/allcs /etc/allcs /var/www/allcs
  for f in api.py report.py; do docker cp $H/server/files/$f $P-web01:/opt/allcs/$f; done
  for f in allcs-api.service allcs-report.service; do docker cp $H/server/files/$f $P-web01:/etc/systemd/system/$f; done
  for f in renew-cert lab-ca-init; do docker cp $H/server/files/$f $P-web01:/usr/local/sbin/$f; done
  docker cp $H/server/files/allcsvideos.conf $P-web01:/etc/nginx/sites-available/allcsvideos
  docker cp $H/server/files/index.html $P-web01:/var/www/allcs/index.html
  apienv $APP_PW | on web01 sh -c 'cat > /etc/allcs/api.env && chown root:www-data /etc/allcs/api.env && chmod 640 /etc/allcs/api.env'
  on web01 sh -c 'chown www-data:www-data /var/log/allcs && chmod 755 /usr/local/sbin/renew-cert /usr/local/sbin/lab-ca-init \
    && lab-ca-init && renew-cert 90 >/dev/null && rm -f /etc/nginx/sites-enabled/default \
    && ln -sf /etc/nginx/sites-available/allcsvideos /etc/nginx/sites-enabled/allcsvideos && nginx -t 2>/dev/null \
    && systemctl daemon-reload && systemctl enable --now nginx allcs-api >/dev/null 2>&1'
  # the app role (FAKE password), once PostgreSQL is up
  local i=0; until on db pg_isready -h localhost -q || (( i++ > 60 )); do sleep 1; done; sleep 2
  on db psql -q -U postgres -d allcs -c "CREATE ROLE allcs_app LOGIN PASSWORD '$APP_PW'; GRANT SELECT ON courses TO allcs_app;"
  # ops: Asha's workstation (host network: talks to the kind API on 127.0.0.1, and to the lab servers by IP)
  docker run -d "${LB[@]}" --name $P-ops --hostname ops --network host --memory 768m \
    --add-host www.allcsvideos.test:$NET.10 --add-host db-01.allcsvideos.test:$NET.20 --add-host web-01:$NET.10 \
    -v /var/run/docker.sock:/var/run/docker.sock $P-ops:1.0 >/dev/null
  on web01 cat /etc/allcs-ca/ca.crt | opsroot sh -c 'cat > /usr/local/share/ca-certificates/allcs-lab-ca.crt && update-ca-certificates 2>/dev/null'
  ops sh -c "printf 'db-01.allcsvideos.test:5432:*:postgres:%s\n' '$SU_PW' > ~/.pgpass && chmod 600 ~/.pgpass && mkdir -p ~/bin ~/incident"
  # Asha is also the DBA: the same superuser .pgpass on web-01 (lab only)
  docker exec -i -u asha -w /home/asha $P-web01 sh -c "printf 'db-01.allcsvideos.test:5432:*:postgres:%s\n' '$SU_PW' > ~/.pgpass && chmod 600 ~/.pgpass"
  docker cp $H/ops/note $P-ops:/home/asha/bin/note; docker cp $H/ops/score $P-ops:/home/asha/bin/score
  opsroot sh -c 'chmod 755 /home/asha/bin/note /home/asha/bin/score && chown -R asha:asha /home/asha/bin && echo "export PATH=\$HOME/bin:\$PATH" >> /home/asha/.bashrc'
  # the ops repo (Module 5 style): a small allcsvideos-ops history
  docker cp $H/repo/. $P-ops:/home/asha/allcsvideos-ops; opsroot chown -R asha:asha /home/asha/allcsvideos-ops
  ops sh -c 'cd allcsvideos-ops && git init -q && git add -A && git commit -qm "ops repo: runbooks, inventory, nginx and kubernetes config" && git log --oneline | head -1'
  # kind cluster + the healthy Kubernetes stack
  docker cp $H/k8s/kind-cluster.yaml $P-ops:/home/asha/kind-cluster.yaml
  docker cp $H/k8s/manifests $P-ops:/home/asha/manifests; opsroot chown -R asha:asha /home/asha/manifests
  ops kind get clusters 2>/dev/null | grep -qx $P || ops kind create cluster --name $P --image $NODE_IMAGE --config /home/asha/kind-cluster.yaml --wait 180s
  ops kind load docker-image $P-api:1.0 --name $P
  ops kubectl apply -f /home/asha/manifests; ops kubectl config set-context --current --namespace=allcs >/dev/null
  ops kubectl -n allcs rollout status deploy/catalog --timeout=180s; ops kubectl -n allcs rollout status deploy/thumbs --timeout=180s
  ops kubectl -n allcs wait --for=condition=Ready pod/client --timeout=180s
  echo "lab up"; status; }
status(){
  printf '%-34s %s\n' "check" "result"
  local c
  c=$(ops curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 -m 8 https://www.allcsvideos.test/api/courses || true); printf '%-34s %s\n' "web-01 /api/courses (TLS)" "$c"
  c=$(on web01 dig +short db-01.allcsvideos.test); printf '%-34s %s\n' "db-01 record (from web-01)" "$c"
  c=$(on web01 df --output=pcent /var/log/allcs | tail -1); printf '%-34s %s\n' "web-01 /var/log/allcs used" "$c"
  c=$(on db psql -U postgres -tAc "select count(*) from pg_stat_activity where backend_type='client backend'"); printf '%-34s %s\n' "db-01 client connections" "$c"
  ops kubectl -n allcs get pods --no-headers | awk '{printf "%-34s %s %s restarts=%s\n", "pod " $1, $2, $3, $4}'
  c=$(ops kubectl -n allcs exec client -- wget -qO- -T 3 http://catalog/courses 2>&1 | head -c 60 || true); printf '%-34s %s\n' "catalog Service (in cluster)" "$c"; }
down(){
  if docker ps --format '{{.Names}}' | grep -qx $P-ops; then ops kind delete cluster --name $P 2>/dev/null || true; fi
  for c in $(docker ps -a --format '{{.Names}} {{.Label "io.x-k8s.kind.cluster"}}' | awk -v p=$P '$2==p {print $1}'); do docker rm -f $c >/dev/null; done
  for c in ops web01 ns1 db; do docker rm -fv $P-$c >/dev/null 2>&1 || true; done
  docker network rm $P-net >/dev/null 2>&1 || true
  docker rmi $P-server:1.0 $P-ops:1.0 $P-api:1.0 >/dev/null 2>&1 || true
  echo "removed $P-* containers, $P-net, the $P images and kind cluster $P (the shared 'kind' network is left alone)"; }
case ${1:-} in
  up) up ;;
  status) status ;;
  ops) docker exec -it -u asha -w /home/asha $P-ops bash ;;
  sh) docker exec -it -u asha -w /home/asha $P-${2:?web01 or ns1} bash ;;
  down) down ;;
  check) docker ps -a --filter name=$P; docker network ls --filter name=$P -q; docker volume ls --filter name=$P -q
         docker images --filter reference="$P*" -q; docker images --format '{{.Repository}}' | grep -E "^(localhost:500[01]/)?$P" || true ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
