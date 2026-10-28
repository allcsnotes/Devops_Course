#!/usr/bin/env bash
# lab.sh: the M18-L02 "Secrets Management" lab. Everything runs in Docker, named secrets-* and labelled course=devops.
#   ./lab.sh up            Gitea + Postgres + Vault (sealed) + the team machine, accounts, the repo as M18-L01 left it,
#                          Priya's fork, main protected against force pushes, clones for priya and rahul
#   ./lab.sh k8s           the kind cluster (Kubernetes 1.36.4) for the External Secrets Operator part
#   ./lab.sh shell NAME    a shell on the team machine as asha, priya or rahul
#   ./lab.sh admin-clean   the Gitea admin's server-side clean-up (delete the pull request ref, garbage-collect)
#   ./lab.sh down          remove everything this lab created (cluster included)
# Network secrets-net 10.0.182.0/24 (fixed addresses: Vault 10.0.182.10, db 10.0.182.11, the kind node 10.0.182.30).
# No cloud credentials anywhere. Every password, key and token here is FAKE or a throwaway lab value (accounts.txt).
set -euo pipefail
cd "$(dirname "$0")"
H=$PWD
V=secrets
L=(--label course=devops --label lab=$V)
G=$V-gitea C=$V-lab N=$V-net T=$V-tools
NODE=kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed
R=http://gitea:3000/allcsvideos/allcsvideos-platform.git
cap() { printf '%s%s' "$(printf %s "${1:0:1}" | tr a-z A-Z)" "${1:1}"; }   # asha -> Asha
gx()  { docker exec -u git $G gitea "$@"; }
api() { local u=$1 m=$2 p=$3 d=${4:-}
        docker exec $C sh -c "curl -s -X $m -H 'Content-Type: application/json' -H \"Authorization: token \$(cat /home/$u/.gitea-token)\" http://gitea:3000/api/v1$p ${d:+-d '$d'}"; }

up() {
  docker network create "${L[@]}" --subnet 10.0.182.0/24 $N >/dev/null
  for v in gitea-data vault-data db-data; do docker volume create "${L[@]}" $V-$v >/dev/null; done
  docker run -d "${L[@]}" --name $G --hostname gitea --network $N --ip 10.0.182.5 --network-alias gitea -p 127.0.0.1:3000:3000 \
    -v $V-gitea-data:/data -e USER_UID=1000 -e USER_GID=1000 \
    -e GITEA__database__DB_TYPE=sqlite3 -e GITEA__security__INSTALL_LOCK=true \
    -e GITEA__server__ROOT_URL=http://gitea:3000/ -e GITEA__server__DOMAIN=gitea -e GITEA__server__DISABLE_SSH=true \
    -e GITEA__service__DISABLE_REGISTRATION=true -e GITEA__repository__DEFAULT_BRANCH=main \
    -e GITEA__time__DEFAULT_UI_LOCATION=Asia/Kolkata -e GITEA__actions__ENABLED=false -e TZ=Asia/Kolkata gitea/gitea:28.1.0 >/dev/null
  docker run -d "${L[@]}" --name $V-db --hostname db --network $N --ip 10.0.182.11 --network-alias db \
    -v $V-db-data:/var/lib/postgresql -v "$H/../db:/docker-entrypoint-initdb.d:ro" \
    -e POSTGRES_DB=catalog -e POSTGRES_PASSWORD=FAKE-lab-postgres-123 -e TZ=Asia/Kolkata postgres:18.6-alpine3.24 >/dev/null
  docker run -d "${L[@]}" --name $V-vault --hostname vault --network $N --ip 10.0.182.10 --network-alias vault \
    -v $V-vault-data:/vault/file -v "$H/../vault:/vault/config:ro" -e TZ=Asia/Kolkata hashicorp/vault:2.1.2 server >/dev/null
  docker build -q "${L[@]}" -t $V-dev image >/dev/null
  docker run -d --init "${L[@]}" --name $C --hostname lab --network $N --ip 10.0.182.6 -e VAULT_ADDR=http://vault:8200 \
    -v "$H/../stages:/stages:ro" $V-dev >/dev/null
  for u in asha priya rahul; do
    docker exec -u $u $C sh -c "git config --global user.name '$(cap $u)' && git config --global user.email $u@example.com && git config --global init.defaultBranch main && git config --global credential.helper store && git config --global advice.detachedHead false && echo 'export VAULT_ADDR=http://vault:8200' >> ~/.bashrc"
  done
  until docker exec $G curl -sf http://localhost:3000/api/healthz >/dev/null 2>&1; do sleep 1; done
  forge; seed; setup
  echo "lab up: Gitea on http://localhost:3000 (accounts in accounts.txt). Vault is sealed: you initialise it."
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
  api asha POST /orgs/allcsvideos/repos '{"name":"allcsvideos-platform","description":"allcsvideos.com: Course Copilot + the security pipeline","default_branch":"main"}' >/dev/null
  td=$(api asha POST /orgs/allcsvideos/teams '{"name":"devs","permission":"write","units":["repo.code","repo.issues","repo.pulls","repo.actions"],"includes_all_repositories":false}' | docker exec -i $C jq .id)
  for u in priya rahul; do api asha PUT /teams/$td/members/$u >/dev/null; done
  api asha PUT /teams/$td/repos/allcsvideos/allcsvideos-platform >/dev/null
}

# the allcsvideos-platform history exactly as M18-L01 left it (same content, authors and dates, so commit 2bce599 matches),
# then the M18-L01 work on branch security-gates, pull request #1, merged into main
seed() {
  local W=/home/asha/allcsvideos-platform
  x() { docker exec -u asha -w $W $C bash -c "$1"; }
  c() { local who=$1 d=$2 msg=$3
        x "git add -A && GIT_AUTHOR_DATE='$d' GIT_COMMITTER_DATE='$d' git -c user.name=$(cap $who) -c user.email=$who@example.com commit -q -m '$msg'"; }
  docker exec -u asha $C mkdir -p $W
  x "git init -q"
  x "cp -r /stages/s1/copilot /stages/s1/VERSION /stages/s1/.gitignore ."; c asha '2026-10-02T11:20:00+05:30' 'copilot 1.5.0: keyword answers and health'
  x "cp -r /stages/s1/infra ."; c rahul '2026-10-06T16:05:00+05:30' 'infra: terraform for the AWS stack (from allcsvideos-aws)'
  x "cp -r /stages/s2/copilot/. copilot/"
  # the staged leak: put the FAKE demo key into the file (split here so GitHub's push protection does not block the course repo)
  K="AKIA2FAKE""DEMOKEYZZZZ"; S="fAkE8dEmO2kEy7oNlY4f""Or9tHe3lAb6x8w7v6u5Q"
  x "sed -i -e 's/__FAKE_AWS_KEY_ID__/$K/' -e 's/__FAKE_AWS_SECRET__/$S/' copilot/app/thumbnails.py"; c priya '2026-10-09T18:42:00+05:30' 'thumbnails: upload course thumbnails to S3'
  x "cp -r /stages/s3/copilot/. copilot/"; c priya '2026-10-10T12:15:00+05:30' 'search: /courses/search with prices from catalog.yaml'
  x "echo 1.6.0 > VERSION"; c asha '2026-10-12T17:30:00+05:30' 'release 1.6.0'
  x "GIT_COMMITTER_DATE='2026-10-12T17:31:00+05:30' git tag -a v1.6.0 -m 'Course Copilot 1.6.0'"
  x "git remote add origin $R && git push -q -u origin main --tags 2>&1 | grep -v remote: || true"
  x "git switch -q -c security-gates && cp -r /stages/s5/. ."; c asha '2026-10-21T22:05:00+05:30' 'security: gates for secrets, code, dependencies and infra'
  x "cp /stages/s6/copilot/app/thumbnails.py copilot/app/"; c priya '2026-10-21T22:11:00+05:30' 'thumbnails: read the S3 key from the environment'
  x "cp /stages/s6/copilot/app/main.py copilot/app/"; c priya '2026-10-21T22:14:00+05:30' 'search: pass the search text as a query parameter'
  x "cp /stages/s6/copilot/requirements.txt copilot/ && cp /stages/s6/trivyignore-empty.yaml .trivyignore.yaml"; c priya '2026-10-21T22:18:00+05:30' 'deps: pyyaml 6.0.3 (CVE-2020-14343)'
  x "cp /stages/s6/gitleaksignore .gitleaksignore"; c rahul '2026-10-21T22:23:00+05:30' 'gitleaks: known 1.6.0 leak, key revoked'
  x "cp -r /stages/l01-final/. ."; c asha '2026-10-21T22:31:00+05:30' 'copilot image: remove pip from the runtime image'
  x "git push -q -u origin security-gates 2>&1 | grep -v remote: || true"
  api asha POST /repos/allcsvideos/allcsvideos-platform/pulls '{"title":"security: gates in the pipeline","head":"security-gates","base":"main","body":"Shift left: gitleaks, semgrep, trivy and checkov as required checks. Threat model in docs/."}' >/dev/null
  api asha POST /repos/allcsvideos/allcsvideos-platform/pulls/1/merge '{"Do":"merge","delete_branch_after_merge":true}' >/dev/null
  x "git switch -q main && git pull -q && git log --oneline --decorate -3"
}

# Priya's fork, main protected against force pushes, fresh clones, and asha's Vault/Kubernetes files in her home
setup() {
  api priya POST /repos/allcsvideos/allcsvideos-platform/forks '{}' >/dev/null
  api asha POST /repos/allcsvideos/allcsvideos-platform/branch_protections '{"rule_name":"main","enable_push":true,"enable_force_push":false}' >/dev/null
  for u in priya rahul; do docker exec -u $u -w /home/$u $C git clone -q $R; done
  docker cp ../vault/. $C:/tmp/vcfg; docker cp ../k8s/manifests/. $C:/tmp/mf
  docker exec $C sh -c 'cp /tmp/vcfg/catalog-read.hcl /tmp/vcfg/catalog-ro.sql /tmp/vcfg/catalog-ro-revoke.sql /tmp/mf/*.yaml /home/asha/ && chown asha:asha /home/asha/*.hcl /home/asha/*.sql /home/asha/*.yaml && rm -rf /tmp/vcfg /tmp/mf'
}

# Force pushes on main: allow for rahul only (allow), and back to fully protected (reprotect). Asha is the admin.
allow()     { api asha PATCH /repos/allcsvideos/allcsvideos-platform/branch_protections/main '{"enable_force_push":true,"enable_force_push_allowlist":true,"force_push_allowlist_usernames":["rahul"]}' | jq -c '{enable_force_push,force_push_allowlist_usernames}'; }
reprotect() { api asha PATCH /repos/allcsvideos/allcsvideos-platform/branch_protections/main '{"enable_force_push":false,"enable_force_push_allowlist":false,"force_push_allowlist_usernames":[]}' | jq -c '{enable_force_push,force_push_allowlist_usernames}'; }

# the server admin's part (on GitHub: GitHub Support): drop the pull request ref, expire reflogs, garbage-collect
admin_clean() {
  local RP=/data/git/repositories/allcsvideos/allcsvideos-platform.git
  for c in "git for-each-ref --format='%(objectname:short) %(refname)' refs/pull" "git update-ref -d refs/pull/1/head" \
           "git reflog expire --expire=now --all && git gc -q --prune=now" "git cat-file -t 2bce599f29fb83dc2007f0f0d0f9423f0dfed0d8"; do
    echo "git@gitea:$RP\$ $c"; docker exec -u git -w $RP $G sh -c "$c" 2>&1 || true
  done
}

# kind cluster "secrets", created from a small tool box (docker CLI + kind v0.33.0); the node joins secrets-net as .30
k8s() {
  docker build -q --label course=devops -t $V-tools:1.0 ../k8s/tools >/dev/null
  docker run -d --name $T --label course=devops --network host -v /var/run/docker.sock:/var/run/docker.sock $V-tools:1.0 sleep infinity >/dev/null
  docker cp ../k8s/kind-cluster.yaml $T:/tmp/kind-cluster.yaml
  docker exec $T kind create cluster --name $V --image $NODE --config /tmp/kind-cluster.yaml --wait 180s
  docker network connect --ip 10.0.182.30 $N $V-control-plane
  docker exec $T kind get kubeconfig --name $V | sed -E 's#server: https://[^ ]+#server: https://10.0.182.30:6443#' |
    docker exec -i -u asha $C sh -c 'mkdir -p ~/.kube && cat > ~/.kube/config && chmod 600 ~/.kube/config'
  docker exec -u asha $C kubectl get nodes
}

down() {
  docker exec $T kind delete cluster --name $V 2>/dev/null || true
  docker rm -f $T 2>/dev/null || true
  docker rm -f -v $C $G $V-vault $V-db 2>/dev/null || true
  for v in $(docker volume ls -q --filter label=lab=$V); do docker volume rm "$v"; done
  docker network rm $N 2>/dev/null || true
  docker image rm $V-dev $V-tools:1.0 2>/dev/null || true
}

case ${1:-} in
  up) up ;;
  k8s) k8s ;;
  shell) docker exec -it -u "${2:?asha, priya or rahul}" -w "/home/$2" $C bash ;;
  allow) allow ;;
  reprotect) reprotect ;;
  admin-clean) admin_clean ;;
  delete-fork) docker exec -u priya $C sh -c "curl -s -o /dev/null -w 'delete fork: HTTP %{http_code}\\n' -X DELETE -H \"Authorization: token \$(cat ~/.gitea-token)\" http://gitea:3000/api/v1/repos/priya/allcsvideos-platform" ;;
  down) down ;;
  *) echo "usage: $0 up | k8s | shell asha|priya|rahul | allow | reprotect | admin-clean | delete-fork | down"; exit 1 ;;
esac
