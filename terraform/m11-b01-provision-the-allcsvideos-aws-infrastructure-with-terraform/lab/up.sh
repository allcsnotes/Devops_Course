#!/usr/bin/env bash
# up.sh: starts the M11-B01 pipeline lab. Everything runs in Docker on your laptop. NO cloud credentials:
# the pipeline only runs checks that need none (fmt, init -backend=false, validate, tflint, checkov).
#   tfci-net      a Docker network for everything below
#   tfci-gitea    gitea/gitea:28.1.0 (Git + web UI + API + Gitea Actions) on http://localhost:3000
#   tfci-team     the team machine (asha, priya, rahul) with git, terraform 1.16.6 and tflint 0.64.0
#   tfci-runner   gitea/runner:5.1.1, runs workflow jobs in gitea/runner-images:ubuntu-24.04-v26.10.01
# Then: accounts (FAKE passwords, see accounts.txt), organisation allcsvideos, repository allcsvideos-aws, team devs.
# Stop the M11-L05 lab first (bash ../m11-l05-environments-and-pipelines/lab/down.sh): both use port 3000.
set -euo pipefail
cd "$(dirname "$0")"
LESSON=$(cd .. && pwd)
P=tfci N=tfci-net G=tfci-gitea C=tfci-team R=tfci-runner
L=(--label lab=$P)

echo "== containers"
docker network create "${L[@]}" $N >/dev/null
docker volume create "${L[@]}" $P-gitea-data >/dev/null
docker volume create "${L[@]}" $P-runner-data >/dev/null
docker run -d "${L[@]}" --name $G --hostname gitea --network $N --network-alias gitea -p 127.0.0.1:3000:3000 \
  -v $P-gitea-data:/data -e USER_UID=1000 -e USER_GID=1000 \
  -e GITEA__database__DB_TYPE=sqlite3 -e GITEA__security__INSTALL_LOCK=true \
  -e GITEA__server__ROOT_URL=http://gitea:3000/ -e GITEA__server__DOMAIN=gitea -e GITEA__server__DISABLE_SSH=true \
  -e GITEA__service__DISABLE_REGISTRATION=true -e GITEA__repository__DEFAULT_BRANCH=main \
  -e GITEA__actions__ENABLED=true gitea/gitea:28.1.0 >/dev/null
docker build -q "${L[@]}" -t $P-team image >/dev/null
docker run -d --init "${L[@]}" --name $C --hostname lab --network $N $P-team >/dev/null
for u in asha priya rahul; do
  docker exec -u $u $C sh -c "git config --global user.name $u && git config --global user.email $u@example.com \
    && git config --global init.defaultBranch main && git config --global credential.helper store"
done
until docker exec $G curl -sf http://localhost:3000/api/healthz >/dev/null 2>&1; do sleep 1; done

echo "== accounts, tokens, organisation, repository, team"
gx() { docker exec -u git $G gitea "$@"; }
gx admin user create --username asha --email asha@example.com --password fake-lab-pass-asha --admin --must-change-password=false >/dev/null
for u in priya rahul; do
  gx admin user create --username $u --email $u@example.com --password fake-lab-pass-$u --must-change-password=false >/dev/null
done
for u in asha priya rahul; do   # one API token per person, stored only inside the team machine
  tok=$(gx admin user generate-access-token --username $u --token-name lab --scopes all --raw)
  docker exec $C sh -c "printf 'http://%s:%s@gitea:3000\n' '$u' '$tok' > /home/$u/.git-credentials && echo '$tok' > /home/$u/.gitea-token \
    && chmod 600 /home/$u/.git-credentials /home/$u/.gitea-token && chown $u:$u /home/$u/.git-credentials /home/$u/.gitea-token"
done
unset tok
api() { # api <user> <method> <path> [json]
  docker exec $C sh -c "curl -s -X $2 -H 'Content-Type: application/json' -H \"Authorization: token \$(cat /home/$1/.gitea-token)\" http://gitea:3000/api/v1$3 ${4:+-d '$4'}"
}
api asha POST /orgs '{"username":"allcsvideos","full_name":"allcsvideos.com","visibility":"public"}' >/dev/null
api asha POST /orgs/allcsvideos/repos '{"name":"allcsvideos-aws","description":"Terraform for the allcsvideos AWS stack (VPC, ALB, ECS on EC2, RDS, S3)","default_branch":"main"}' >/dev/null
TD=$(api asha POST /orgs/allcsvideos/teams '{"name":"devs","permission":"write","units":["repo.code","repo.issues","repo.pulls","repo.actions"],"includes_all_repositories":false}' | docker exec -i $C jq .id)
for u in priya rahul; do api asha PUT /teams/$TD/members/$u >/dev/null; done
api asha PUT /teams/$TD/repos/allcsvideos/allcsvideos-aws >/dev/null

echo "== runner"
RTOK=$(docker exec -u git $G gitea actions generate-runner-token 2>&1 | tail -1)
docker run -d "${L[@]}" --name $R --hostname runner-01 --network $N \
  -v /var/run/docker.sock:/var/run/docker.sock -v $P-runner-data:/data \
  -v "$PWD/runner/config.yaml":/config.yaml:ro -e CONFIG_FILE=/config.yaml \
  -e GITEA_INSTANCE_URL=http://gitea:3000/ -e GITEA_RUNNER_REGISTRATION_TOKEN="$RTOK" -e GITEA_RUNNER_NAME=runner-01 \
  gitea/runner:5.1.1 >/dev/null
unset RTOK
for i in $(seq 1 30); do docker logs $R 2>&1 | grep -q 'declare successfully' && break; sleep 1; done

echo "== project files for the team machine (/tmp/repo-src, /tmp/stage)"
docker cp "$LESSON/allcsvideos-aws" $C:/tmp/repo-src
docker cp "$LESSON/stage" $C:/tmp/stage
docker exec $C chmod -R a+rX /tmp/repo-src /tmp/stage

echo
echo "lab up: open http://localhost:3000 (accounts in lab/accounts.txt)"
echo "shell as asha:  docker exec -it -u asha -w /home/asha tfci-team bash"
