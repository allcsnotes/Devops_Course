#!/usr/bin/env bash
# lab.sh: the M18-L01 "Shift Left" lab (the Module 8 CI lab, renamed "shiftleft"). Everything runs in Docker.
#   ./lab.sh up            Gitea + the team machine + accounts + the seeded repository + the Actions runner
#   ./lab.sh shell NAME    a shell on the team machine as asha, priya or rahul (stands in for three laptops)
#   ./lab.sh protect       make the four security checks required on main (branch protection, as asha)
#   ./lab.sh down          remove everything this lab created
# Containers:
#   shiftleft-gitea   gitea/gitea:28.1.0 (Git + web UI + API + Gitea Actions), http://localhost:3000
#   shiftleft-lab     the team machine (image shiftleft-dev): asha, priya, rahul + gitleaks, semgrep, trivy
#   shiftleft-runner  gitea/runner:5.1.1, jobs run in gitea/runner-images:ubuntu-24.04-v26.10.01
# No cloud credentials anywhere. Every password, key and token in this lab is FAKE (see accounts.txt).
set -euo pipefail
cd "$(dirname "$0")"
V=shiftleft
L=(--label course=devops --label lab=$V)
G=$V-gitea C=$V-lab N=$V-net R=$V-runner
cap() { printf '%s%s' "$(printf %s "${1:0:1}" | tr a-z A-Z)" "${1:1}"; }   # asha -> Asha (works in bash 3.2 too)
gx()  { docker exec -u git $G gitea "$@"; }
api() { local u=$1 m=$2 p=$3 d=${4:-}
        docker exec $C sh -c "curl -s -X $m -H 'Content-Type: application/json' -H \"Authorization: token \$(cat /home/$u/.gitea-token)\" http://gitea:3000/api/v1$p ${d:+-d '$d'}"; }

up() {
  docker network create "${L[@]}" $N >/dev/null
  docker volume create "${L[@]}" $V-gitea-data >/dev/null
  docker run -d "${L[@]}" --name $G --hostname gitea --network $N --network-alias gitea -p 127.0.0.1:3000:3000 \
    -v $V-gitea-data:/data -e USER_UID=1000 -e USER_GID=1000 \
    -e GITEA__database__DB_TYPE=sqlite3 -e GITEA__security__INSTALL_LOCK=true \
    -e GITEA__server__ROOT_URL=http://gitea:3000/ -e GITEA__server__DOMAIN=gitea -e GITEA__server__DISABLE_SSH=true \
    -e GITEA__service__DISABLE_REGISTRATION=true -e GITEA__repository__DEFAULT_BRANCH=main \
    -e GITEA__time__DEFAULT_UI_LOCATION=Asia/Kolkata -e GITEA__actions__ENABLED=true -e TZ=Asia/Kolkata \
    gitea/gitea:28.1.0 >/dev/null
  docker build -q "${L[@]}" -t $V-dev image >/dev/null
  # the lesson's files (../stages) are mounted read-only at /stages on the team machine
  docker run -d --init "${L[@]}" --name $C --hostname lab --network $N -v "$PWD/../stages:/stages:ro" $V-dev >/dev/null
  for u in asha priya rahul; do
    docker exec -u $u $C sh -c "git config --global user.name '$(cap $u)' && git config --global user.email $u@example.com && git config --global init.defaultBranch main && git config --global credential.helper store && git config --global advice.detachedHead false"
  done
  until docker exec $G curl -sf http://localhost:3000/api/healthz >/dev/null 2>&1; do sleep 1; done
  forge; seed; runner
  echo "lab up: Gitea on http://localhost:3000 (accounts in accounts.txt)"
}

# accounts (FAKE passwords), one API token per account (generated inside the lab, never printed),
# organisation allcsvideos, repository allcsvideos-platform, team devs (write: priya, rahul)
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
  echo "forge ready"
}

# the repository history, with past dates and real authors, pushed to Gitea. Release 1.6.0 went out on 2026-10-12.
#  s1  2026-10-02 asha   Course Copilot 1.5.0           2026-10-06 rahul  infra: the Terraform project from M11-B01
#  s2  2026-10-09 priya  thumbnails uploader            (a FAKE AWS key hard-coded: the staged leak)
#  s3  2026-10-10 priya  /courses/search + catalog.yaml (DELIBERATELY VULNERABLE: SQL built with an f-string; pyyaml 5.3.1)
#  s4  2026-10-12 asha   release 1.6.0, tag v1.6.0
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
  x "git remote add origin http://gitea:3000/allcsvideos/allcsvideos-platform.git && git push -q -u origin main --tags 2>&1 | grep -v remote: ; git log --oneline --decorate"
  for u in priya rahul; do docker exec -u $u -w /home/$u $C git clone -q http://gitea:3000/allcsvideos/allcsvideos-platform.git; done
}

# the Actions runner: registration token from Gitea's CLI (never printed)
runner() {
  tok=$(docker exec -u git $G gitea actions generate-runner-token 2>&1 | tail -1)
  docker volume create "${L[@]}" $V-runner-data >/dev/null
  docker run -d "${L[@]}" --name $R --hostname runner-01 --network $N \
    -v /var/run/docker.sock:/var/run/docker.sock -v $V-runner-data:/data \
    -v "$PWD/runner/config.yaml:/config.yaml:ro" -e CONFIG_FILE=/config.yaml \
    -e GITEA_INSTANCE_URL=http://gitea:3000/ -e GITEA_RUNNER_REGISTRATION_TOKEN="$tok" -e GITEA_RUNNER_NAME=runner-01 \
    gitea/runner:5.1.1 >/dev/null
  unset tok
  for i in $(seq 1 30); do docker logs $R 2>&1 | grep -q 'declare successfully' && break; sleep 1; done
  docker logs $R 2>&1 | grep -v -i token | tail -3
}

protect() {
  docker exec $C sh -c "curl -s -o /dev/null -w 'protect main: HTTP %{http_code}\n' -X POST -H 'Content-Type: application/json' -H \"Authorization: token \$(cat /home/asha/.gitea-token)\" http://gitea:3000/api/v1/repos/allcsvideos/allcsvideos-platform/branch_protections -d '{\"rule_name\":\"main\",\"enable_push\":false,\"enable_status_check\":true,\"status_check_contexts\":[\"security / secrets (pull_request)\",\"security / sast (pull_request)\",\"security / deps (pull_request)\",\"security / iac (pull_request)\"]}'"
}

down() {
  docker rm -f $R 2>/dev/null || true
  # only the job containers on THIS lab's network
  for c in $(docker ps -aq --filter network=$N --filter name=GITEA-ACTIONS); do
    vols=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}' "$c")
    docker rm -f -v "$c"
    for v in $vols; do case $v in GITEA-ACTIONS*) docker volume rm "$v" 2>/dev/null || true ;; esac; done
  done
  docker rm -f -v $C $G $V-copilot 2>/dev/null || true
  for v in $(docker volume ls -q --filter label=lab=$V); do docker volume rm "$v"; done
  docker network rm $N 2>/dev/null || true
  docker image rm $V-dev $V-copilot:1.6.1 $V-copilot:1.6.1-nopip 2>/dev/null || true
}

case ${1:-} in
  up) up ;;
  shell) docker exec -it -u "${2:?asha, priya or rahul}" -w "/home/$2/allcsvideos-platform" $C bash ;;
  protect) protect ;;
  down) down ;;
  *) echo "usage: $0 up | shell asha|priya|rahul | protect | down"; exit 1 ;;
esac
