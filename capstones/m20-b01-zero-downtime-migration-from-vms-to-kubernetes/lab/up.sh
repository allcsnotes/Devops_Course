#!/bin/bash
# up.sh: builds the whole migration lab on your laptop with Docker.
#   "Before" world: web-01 and web-02, two Ubuntu "VMs" (containers with systemd + SSH), configured by Ansible.
#   "After" world:  a one-node kind cluster with Argo CD (core install).
#   Shared:         one PostgreSQL, one nginx edge load balancer, Prometheus, a Gitea server for the deploy repo,
#                   and an "ops" box (Ansible, kubectl, helm, kind, psql) where you type every lesson command.
#
# Usage:  bash lab/up.sh            (takes 5-10 minutes the first time: image builds + kind cluster)
#
# Lab network mig-net 10.0.201.0/24:
#   .5 edge (nginx)  .10 ops  .11 web-01  .12 web-02  .20 db (postgres)  .30 prometheus  .31 grafana
#   .40 gitea  .50 k6 (while a test runs)  .60 the kind node
# Ports on your laptop (127.0.0.1 only): 9090 Prometheus, 3001 Gitea, 3000 Grafana (only after lab/grafana.sh).
#
# Your working copy: the lesson's migration/ folder is copied ONCE to $WORK (default ~/migration-lab) and mounted
# into the ops box as /home/asha/migration. Edit files there, not in the course repo.
# All passwords below are FAKE lab values.
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HOME/migration-lab}
P=mig; NET=10.0.201; L=(--label course=devops)
NODE_IMAGE=kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed
SYS=(--privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock)   # systemd as PID 1 inside the "VMs"
exists(){ docker ps -a --format '{{.Names}}' | grep -qx "$1"; }
ops(){ docker exec -i $P-ops bash -lc "export PATH=\$HOME/.venvs/ansible/bin:\$HOME/migration/bin:\$PATH; $1"; }

# 0. your working copy
[ -d "$WORK" ] || { cp -R "$H/../migration" "$WORK"; echo "copied migration/ to $WORK"; }
chmod +x "$WORK"/bin/*

# 1. images, volumes, network
docker build -q -t $P-vm:1.0 "${L[@]}" "$H/images/vm" >/dev/null
docker build -q -t $P-ops:1.0 "${L[@]}" "$H/images/ops" >/dev/null
for v in pgdata tsdb gitea-data; do docker volume ls -q | grep -qx $P-$v || docker volume create "${L[@]}" $P-$v >/dev/null; done
docker network ls --format '{{.Name}}' | grep -qx $P-net || docker network create "${L[@]}" --subnet $NET.0/24 $P-net >/dev/null

# 2. the shared database: max_connections 30 on purpose (a small instance, so the connection budget matters)
exists $P-db || docker run -d "${L[@]}" --name $P-db --hostname db --network $P-net --ip $NET.20 --memory 256m --cpus 1 \
  -e POSTGRES_DB=catalog -e POSTGRES_PASSWORD=demo-password-123 \
  -v $P-pgdata:/var/lib/postgresql -v "$H/db":/docker-entrypoint-initdb.d:ro \
  postgres:18.6-alpine3.24 -c max_connections=30 -c log_connections=off >/dev/null

# 3. the two VMs (half a CPU each, the same as each pod later), the ops box, the edge, Prometheus, Gitea
for n in web-01:11 web-02:12; do h=${n%%:*}; exists $P-${h//-/} || docker run -d "${L[@]}" "${SYS[@]}" --name $P-${h//-/} \
  --hostname $h --network $P-net --ip $NET.${n##*:} --memory 384m --cpus 0.5 $P-vm:1.0 >/dev/null; done
exists $P-ops || docker run -d "${L[@]}" --name $P-ops --hostname ops --network $P-net --ip $NET.10 --memory 768m \
  -v /var/run/docker.sock:/var/run/docker.sock -v "$WORK":/home/asha/migration -e TERM=xterm-256color $P-ops:1.0 >/dev/null
exists $P-edge || docker run -d "${L[@]}" --name $P-edge --hostname edge --network $P-net --ip $NET.5 --memory 64m --cpus 0.5 \
  -v "$WORK/edge/nginx.conf":/etc/nginx/nginx.conf:ro -v "$WORK/edge/split":/etc/nginx/split:ro nginx:1.29.8-alpine >/dev/null
exists $P-prometheus || docker run -d "${L[@]}" --name $P-prometheus --hostname prometheus --network $P-net --ip $NET.30 \
  --memory 384m -p 127.0.0.1:9090:9090 -v "$H/prometheus":/etc/prometheus:ro -v $P-tsdb:/prometheus \
  prom/prometheus:v3.15.0 --config.file=/etc/prometheus/prometheus.yml --web.enable-remote-write-receiver >/dev/null
exists $P-gitea || docker run -d "${L[@]}" --name $P-gitea --hostname gitea --network $P-net --ip $NET.40 --memory 384m \
  -p 127.0.0.1:3001:3000 -v $P-gitea-data:/data -e USER_UID=1000 -e USER_GID=1000 -e GITEA__database__DB_TYPE=sqlite3 \
  -e GITEA__security__INSTALL_LOCK=true -e GITEA__server__ROOT_URL=http://$NET.40:3000/ -e GITEA__server__DISABLE_SSH=true \
  -e GITEA__service__DISABLE_REGISTRATION=true -e GITEA__repository__DEFAULT_BRANCH=main -e GITEA__actions__ENABLED=false \
  gitea/gitea:28.1.0 >/dev/null

# 4. Asha's SSH key on the ops box (lab-only key), then each VM is set up bare, like a fresh cloud VM (M12-B01 recipe)
ops 'test -f ~/.ssh/id_ed25519 || ssh-keygen -q -t ed25519 -C asha@example.com -N "" -f ~/.ssh/id_ed25519
  ln -sfn ~/migration/bin ~/bin                                               # gate.sh, shift.sh, ... as plain commands
  echo "10.0.201.20:5432:*:postgres:demo-password-123" > ~/.pgpass && chmod 600 ~/.pgpass'   # psql as postgres (FAKE)
KEY=$(docker exec $P-ops cat /home/asha/.ssh/id_ed25519.pub); sleep 4
for h in web01 web02; do docker exec $P-$h id asha >/dev/null 2>&1 && continue
  docker cp "$H/setup-node.sh" $P-$h:/root/ && docker exec $P-$h bash /root/setup-node.sh "$KEY"; done

# 5. Gitea: admin asha (FAKE password), org allcsvideos, empty repo allcsvideos-deploy (Argo CD reads it without credentials)
until docker exec $P-gitea curl -sf http://localhost:3000/api/healthz >/dev/null 2>&1; do sleep 1; done
if ! docker exec -u git $P-gitea gitea admin user list | grep -q asha; then
  docker exec -u git $P-gitea gitea admin user create --username asha --email asha@example.com --password fake-lab-pass-asha \
    --admin --must-change-password=false --fullname Asha >/dev/null
  T=$(docker exec -u git $P-gitea gitea admin user generate-access-token --username asha --token-name lab --scopes all --raw)
  ops "printf 'http://asha:%s@$NET.40:3000\n' '$T' > ~/.git-credentials && chmod 600 ~/.git-credentials
    git config --global user.name Asha && git config --global user.email asha@example.com
    git config --global init.defaultBranch main && git config --global credential.helper store && git config --global core.pager cat
    curl -s -X POST -H 'Content-Type: application/json' -H 'Authorization: token $T' http://$NET.40:3000/api/v1/orgs -d '{\"username\":\"allcsvideos\"}' >/dev/null
    curl -s -X POST -H 'Content-Type: application/json' -H 'Authorization: token $T' http://$NET.40:3000/api/v1/orgs/allcsvideos/repos -d '{\"name\":\"allcsvideos-deploy\",\"private\":false,\"default_branch\":\"main\"}' >/dev/null"
  unset T
fi

# 6. Ansible vault (FAKE password file outside the repo), then the module-12 baseline: the API on both VMs
ops 'test -f ~/.vault-pass.txt || { echo fake-lab-vault-pass > ~/.vault-pass.txt; chmod 600 ~/.vault-pass.txt; }
  cd ~/migration/ansible && { test -f group_vars/web/vault.yml || ansible-vault encrypt --output group_vars/web/vault.yml group_vars/web/vault.plain.yml; }
  ansible-playbook site.yml | tail -4'

# 7. the kind cluster (one node), joined to the lab network at .60, plus Argo CD core
ops "kind get clusters 2>/dev/null | grep -qx $P" || \
  ops "kind create cluster --name $P --image $NODE_IMAGE --config ~/migration/kind/kind-cluster.yaml --wait 300s"
docker inspect $P-control-plane --format '{{json .NetworkSettings.Networks}}' | grep -q $P-net || \
  docker network connect --ip $NET.60 $P-net $P-control-plane
ops "kind export kubeconfig --name $P --internal >/dev/null 2>&1; kubectl get nodes"
ops 'kubectl apply -k ~/migration/argocd/ --server-side --force-conflicts >/dev/null && kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s'

echo "lab up. Open a shell on the ops box:  docker exec -it -w /home/asha/migration $P-ops bash"
