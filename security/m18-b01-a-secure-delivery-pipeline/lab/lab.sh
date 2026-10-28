#!/usr/bin/env bash
# lab.sh: the M18-B01 "A Secure Delivery Pipeline" lab. Built from the M18-L01 CI lab (Gitea + runner + gates), the
# M18-L03 registry and signing, and the M18-L04 kind + Kyverno lab. Everything runs in Docker, named securepipe-*.
#   ./lab.sh up          Gitea, the lab registry, the CI Docker daemon, the team machine, accounts, the kind cluster,
#                        Kyverno (admission controller only), the runner, and the repository history before this build
#   ./lab.sh shell NAME  a shell on the team machine as asha, priya or rahul (in ~/allcsvideos-platform when it exists)
#   ./lab.sh protect     branch protection on main: no pushes, the four pipeline gates required (step 6)
#   ./lab.sh down        remove everything this lab created (the shared "kind" network is left alone)
# Containers:
#   securepipe-gitea     gitea/gitea:28.1.0 (Git, web UI, REST API, Gitea Actions), http://localhost:3000
#   securepipe-registry  registry:3.1.2 as registry.lab:5000 (plain HTTP, accepts any push: lab only)
#   securepipe-docker    docker:29.5.3-dind, the CI jobs' Docker daemon (TLS on docker:2376): release images are built here
#   securepipe-lab       the team machine: git, gitleaks, uv, kind, kubectl, helm, cosign, docker CLI
#   securepipe-runner    gitea/runner:5.1.1
#   securepipe           kind cluster (one node, kindest/node v1.35.8); the node also joins securepipe-net
# Every password, token and key in this lab is FAKE or lab-only (accounts.txt).
set -euo pipefail
cd "$(dirname "$0")"
HERE=$PWD; ROOT=$(dirname "$HERE")
V=securepipe
L=(--label course=devops --label lab=$V)
G=$V-gitea C=$V-lab N=$V-net R=$V-runner REG=$V-registry DD=$V-docker
NODE_IMAGE=kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0
cap() { printf '%s%s' "$(printf %s "${1:0:1}" | tr a-z A-Z)" "${1:1}"; }   # asha -> Asha
gx()  { docker exec -u git $G gitea "$@"; }
api() { local u=$1 m=$2 p=$3 d=${4:-}
        docker exec $C sh -c "curl -s -X $m -H 'Content-Type: application/json' -H \"Authorization: token \$(cat /home/$u/.gitea-token)\" http://gitea:3000/api/v1$p ${d:+-d '$d'}"; }

up() {
  docker network create "${L[@]}" $N >/dev/null
  for v in gitea-data registry-data dind-certs dind-data; do docker volume create "${L[@]}" $V-$v >/dev/null; done
  docker run -d "${L[@]}" --name $G --hostname gitea --network $N --network-alias gitea -p 127.0.0.1:3000:3000 \
    -v $V-gitea-data:/data -e USER_UID=1000 -e USER_GID=1000 \
    -e GITEA__database__DB_TYPE=sqlite3 -e GITEA__security__INSTALL_LOCK=true \
    -e GITEA__server__ROOT_URL=http://gitea:3000/ -e GITEA__server__DOMAIN=gitea -e GITEA__server__DISABLE_SSH=true \
    -e GITEA__service__DISABLE_REGISTRATION=true -e GITEA__repository__DEFAULT_BRANCH=main \
    -e GITEA__time__DEFAULT_UI_LOCATION=Asia/Kolkata -e GITEA__actions__ENABLED=true -e TZ=Asia/Kolkata gitea/gitea:28.1.0 >/dev/null
  docker run -d "${L[@]}" --name $REG --hostname registry --network $N --network-alias registry.lab \
    -v $V-registry-data:/var/lib/registry registry:3.1.2 >/dev/null
  docker run -d "${L[@]}" --name $DD --hostname docker --network $N --network-alias docker \
    -v $V-dind-certs:/certs -v $V-dind-data:/var/lib/docker \
    --privileged -e DOCKER_TLS_CERTDIR=/certs docker:29.5.3-dind --insecure-registry registry.lab:5000 >/dev/null
  docker build -q "${L[@]}" -t $V-lab-img image >/dev/null
  docker run -d --init "${L[@]}" --name $C --hostname lab --network $N -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$ROOT/repo:/lesson/repo:ro" -v "$ROOT/stages:/lesson/stages:ro" $V-lab-img >/dev/null
  docker cp gitea-secret $C:/usr/local/bin/gitea-secret
  docker cp deployer-kubeconfig $C:/usr/local/bin/deployer-kubeconfig
  docker cp laptop-buildkitd.toml $C:/etc/laptop-buildkitd.toml
  docker exec $C chmod 755 /usr/local/bin/gitea-secret /usr/local/bin/deployer-kubeconfig
  for u in asha priya rahul; do
    docker exec -u $u $C sh -c "git config --global user.name '$(cap $u)' && git config --global user.email $u@example.com && git config --global init.defaultBranch main && git config --global credential.helper store && git config --global advice.detachedHead false && git config --global pull.rebase false"
  done
  until docker exec $G curl -sf http://localhost:3000/api/healthz >/dev/null 2>&1; do sleep 1; done
  until docker exec $DD docker info >/dev/null 2>&1; do sleep 1; done
  forge; cluster; kyverno; runner; seed
  echo "lab up: Gitea on http://localhost:3000 (accounts in accounts.txt)"
}

forge() {
  gx admin user create --username asha --email asha@example.com --password fake-lab-pass-asha --admin --must-change-password=false --fullname Asha >/dev/null
  for u in priya rahul; do
    gx admin user create --username $u --email $u@example.com --password fake-lab-pass-$u --must-change-password=false --fullname "$(cap $u)" >/dev/null
  done
  for u in asha priya rahul; do
    tok=$(gx admin user generate-access-token --username $u --token-name lab --scopes all --raw)
    docker exec $C sh -c "printf 'http://%s:%s@gitea:3000\n' '$u' '$tok' > /home/$u/.git-credentials && echo '$tok' > /home/$u/.gitea-token && chmod 600 /home/$u/.git-credentials /home/$u/.gitea-token && chown $u:$u /home/$u/.git-credentials /home/$u/.gitea-token"
  done
  unset tok
  api asha POST /orgs '{"username":"allcsvideos","full_name":"allcsvideos.com","visibility":"public"}' >/dev/null
  api asha POST /orgs/allcsvideos/repos '{"name":"allcsvideos-platform","description":"allcsvideos.com: Course Copilot and its secure delivery pipeline","default_branch":"main"}' >/dev/null
  td=$(api asha POST /orgs/allcsvideos/teams '{"name":"devs","permission":"write","units":["repo.code","repo.issues","repo.pulls","repo.actions"],"includes_all_repositories":false}' | docker exec -i $C jq .id)
  for u in priya rahul; do api asha PUT /teams/$td/members/$u >/dev/null; done
  api asha PUT /teams/$td/repos/allcsvideos/allcsvideos-platform >/dev/null
}

# the kind cluster; its node joins the lab network (CI jobs reach the API server as securepipe-control-plane:6443)
# and pulls from registry.lab:5000 over plain HTTP (containerd hosts.toml, lab only)
cluster() {
  docker cp kind-cluster.yaml $C:/home/asha/kind-cluster.yaml
  docker exec -u asha $C kind create cluster --name $V --image $NODE_IMAGE --config /home/asha/kind-cluster.yaml --wait 300s
  docker network connect $N $V-control-plane
  docker exec $V-control-plane mkdir -p /etc/containerd/certs.d/registry.lab:5000
  printf '[host."http://registry.lab:5000"]\n  capabilities = ["pull", "resolve"]\n' | docker exec -i $V-control-plane cp /dev/stdin /etc/containerd/certs.d/registry.lab:5000/hosts.toml
  for u in asha priya; do   # in this lab Priya has the admin kubeconfig too (break 1 shows why that doesn't matter)
    docker exec -u $u $C sh -c "mkdir -p ~/.kube && kind get kubeconfig --internal --name $V > ~/.kube/config && chmod 600 ~/.kube/config"
  done
}

# Kyverno 1.19.2 (chart 3.9.2), admission controller only (cluster/kyverno-values.yaml)
kyverno() {
  docker exec -u asha $C sh -c "helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null && helm install kyverno kyverno/kyverno --version 3.9.2 -n kyverno --create-namespace -f /lesson/repo/cluster/kyverno-values.yaml --wait --timeout 10m >/dev/null"
}

runner() {
  tok=$(docker exec -u git $G gitea actions generate-runner-token 2>&1 | tail -1)
  docker volume create "${L[@]}" $V-runner-data >/dev/null
  docker run -d "${L[@]}" --name $R --hostname runner-01 --network $N \
    -v /var/run/docker.sock:/var/run/docker.sock -v $V-runner-data:/data \
    -v "$HERE/runner/config.yaml:/config.yaml:ro" -e CONFIG_FILE=/config.yaml \
    -e GITEA_INSTANCE_URL=http://gitea:3000/ -e GITEA_RUNNER_REGISTRATION_TOKEN="$tok" -e GITEA_RUNNER_NAME=runner-01 \
    gitea/runner:5.1.1 >/dev/null
  unset tok
  for i in $(seq 1 30); do docker logs $R 2>&1 | grep -q 'declare successfully' && break; sleep 1; done
}

# the repository before this build (real past dates):
#  2026-10-06 rahul  infra: the Terraform project      2026-10-21 asha  lesson 1: Copilot 1.6.0 + the four gates
#  2026-10-21 asha   lesson 3: Copilot 1.7.0, dependencies locked with hashes, base image by digest
seed() {
  local W=/home/asha/allcsvideos-platform
  x() { docker exec -u asha -w $W $C bash -c "$1"; }
  c() { local who=$1 d=$2 msg=$3
        x "git add -A && GIT_AUTHOR_DATE='$d' GIT_COMMITTER_DATE='$d' git -c user.name=$(cap $who) -c user.email=$who@example.com commit -q -m '$msg'"; }
  docker exec -u asha $C mkdir -p $W
  x "git init -q"
  x "cp -r /lesson/stages/s1/infra ."; c rahul '2026-10-06T16:05:00+05:30' 'infra: terraform for the AWS stack'
  x "cp -r /lesson/stages/s2/. ."; c asha '2026-10-21T18:40:00+05:30' 'security: four gates for secrets, code, dependencies and infra'
  x "rm -rf copilot && cp -r /lesson/repo/copilot . && echo 1.7.0 > VERSION"; c asha '2026-10-21T23:30:00+05:30' 'copilot 1.7.0: dependencies locked with hashes, base image by digest'
  x "git remote add origin http://gitea:3000/allcsvideos/allcsvideos-platform.git && git push -q -u origin main 2>&1 | grep -v remote: || true"
}

protect() {
  docker exec $C sh -c "curl -s -o /dev/null -w 'protect main: HTTP %{http_code}\n' -X POST -H 'Content-Type: application/json' -H \"Authorization: token \$(cat /home/asha/.gitea-token)\" http://gitea:3000/api/v1/repos/allcsvideos/allcsvideos-platform/branch_protections -d '{\"rule_name\":\"main\",\"enable_push\":false,\"enable_status_check\":true,\"status_check_contexts\":[\"pipeline / secrets (pull_request)\",\"pipeline / sast (pull_request)\",\"pipeline / deps (pull_request)\",\"pipeline / iac (pull_request)\"]}'"
}

down() {
  docker rm -f $R 2>/dev/null || true
  for c in $(docker ps -aq --filter network=$N --filter name=GITEA-ACTIONS); do
    vols=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}' "$c")
    docker rm -f -v "$c"
    for v in $vols; do case $v in GITEA-ACTIONS*) docker volume rm "$v" 2>/dev/null || true ;; esac; done
  done
  docker exec $C kind delete cluster --name $V 2>/dev/null || true
  for c in $(docker ps -a --format '{{.Names}} {{.Label "io.x-k8s.kind.cluster"}}' | awk -v p=$V '$2==p {print $1}'); do docker rm -f "$c" >/dev/null; done
  docker buildx rm $V-laptop 2>/dev/null || true
  for c in $(docker ps -aq --filter name=buildx_buildkit_$V); do docker rm -f -v "$c"; done
  docker rm -f -v $C $G $REG $DD 2>/dev/null || true
  for v in $(docker volume ls -q --filter label=lab=$V) $(docker volume ls -q --filter name=buildx_buildkit_$V); do docker volume rm "$v"; done
  docker network rm $N 2>/dev/null || true
  docker image rm $V-lab-img 2>/dev/null || true
  echo "lab down"
}

case ${1:-} in
  up) up ;;
  shell) docker exec -it -u "${2:?asha, priya or rahul}" $C bash -c "cd ~/allcsvideos-platform 2>/dev/null || cd ~; exec bash" ;;
  protect) protect ;;
  down) down ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
