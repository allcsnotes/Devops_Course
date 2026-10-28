#!/usr/bin/env bash
# up.sh: starts the M11-L05 pipeline lab. Everything runs in Docker on your laptop, no cloud.
#   tflab-net       a Docker network for everything below
#   tflab-gitea     gitea/gitea:28.1.0 (Git + web UI + API + Gitea Actions) on http://localhost:3000
#   tflab-tfstate   postgres:18.6-alpine3.24: the Terraform state backend ("pg", one schema per environment)
#   tflab-team      the team machine (asha, priya, rahul) with git, terraform 1.16.6 and tflint 0.64.0
#   tflab-runner    gitea/runner:5.1.1, runs workflow jobs in gitea/runner-images:ubuntu-24.04-v26.10.01
# Then it creates the accounts, the allcsvideos organisation, two repositories, two teams,
# the state database roles and the Actions secrets. All passwords are FAKE (see accounts.txt).
set -euo pipefail
cd "$(dirname "$0")"
LESSON=$(cd .. && pwd)
P=tflab N=tflab-net G=tflab-gitea DB=tflab-tfstate C=tflab-team R=tflab-runner
L=(--label lab=$P)

echo "== containers"
docker network create "${L[@]}" $N >/dev/null
docker volume create "${L[@]}" $P-gitea-data >/dev/null
docker volume create "${L[@]}" $P-tfstate-data >/dev/null
docker volume create "${L[@]}" $P-runner-data >/dev/null
docker run -d "${L[@]}" --name $G --hostname gitea --network $N --network-alias gitea -p 127.0.0.1:3000:3000 \
  -v $P-gitea-data:/data -e USER_UID=1000 -e USER_GID=1000 \
  -e GITEA__database__DB_TYPE=sqlite3 -e GITEA__security__INSTALL_LOCK=true \
  -e GITEA__server__ROOT_URL=http://gitea:3000/ -e GITEA__server__DOMAIN=gitea -e GITEA__server__DISABLE_SSH=true \
  -e GITEA__service__DISABLE_REGISTRATION=true -e GITEA__repository__DEFAULT_BRANCH=main \
  -e GITEA__actions__ENABLED=true gitea/gitea:28.1.0 >/dev/null
docker run -d "${L[@]}" --name $DB --hostname tfstate --network $N --network-alias tfstate \
  -v $P-tfstate-data:/var/lib/postgresql -e POSTGRES_USER=tfstate -e POSTGRES_PASSWORD=fake-lab-pass-tfstate \
  -e POSTGRES_DB=tfstate postgres:18.6-alpine3.24 >/dev/null
docker build -q "${L[@]}" -t $P-team image >/dev/null
docker run -d --init "${L[@]}" --name $C --hostname lab --network $N $P-team >/dev/null
for u in asha priya rahul; do
  docker exec -u $u $C sh -c "git config --global user.name $u && git config --global user.email $u@example.com \
    && git config --global init.defaultBranch main && git config --global credential.helper store"
done
until docker exec $G curl -sf http://localhost:3000/api/healthz >/dev/null 2>&1; do sleep 1; done
until docker exec $DB pg_isready -h localhost -U tfstate >/dev/null 2>&1; do sleep 1; done

echo "== accounts, tokens, organisation, repositories, teams"
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
api asha POST /orgs/allcsvideos/repos '{"name":"allcsvideos-infra","description":"Terraform for allcsvideos.com (lab: stand-in resources, no cloud)","default_branch":"main"}' >/dev/null
api asha POST /orgs/allcsvideos/repos '{"name":"infra-production","description":"Production applies (releasers only)","default_branch":"main","private":true}' >/dev/null
TD=$(api asha POST /orgs/allcsvideos/teams '{"name":"devs","permission":"write","units":["repo.code","repo.issues","repo.pulls","repo.actions"],"includes_all_repositories":false}' | docker exec -i $C jq .id)
TR=$(api asha POST /orgs/allcsvideos/teams '{"name":"releasers","permission":"write","units":["repo.code","repo.issues","repo.pulls","repo.actions"],"includes_all_repositories":false}' | docker exec -i $C jq .id)
for u in priya rahul; do api asha PUT /teams/$TD/members/$u >/dev/null; done
api asha PUT /teams/$TR/members/rahul >/dev/null
api asha PUT /teams/$TD/repos/allcsvideos/allcsvideos-infra >/dev/null
api asha PUT /teams/$TR/repos/allcsvideos/infra-production >/dev/null

echo "== runner"
RTOK=$(docker exec -u git $G gitea actions generate-runner-token 2>&1 | tail -1)
docker run -d "${L[@]}" --name $R --hostname runner-01 --network $N \
  -v /var/run/docker.sock:/var/run/docker.sock -v $P-runner-data:/data \
  -v "$PWD/runner/config.yaml":/config.yaml:ro -e CONFIG_FILE=/config.yaml \
  -e GITEA_INSTANCE_URL=http://gitea:3000/ -e GITEA_RUNNER_REGISTRATION_TOKEN="$RTOK" -e GITEA_RUNNER_NAME=runner-01 \
  gitea/runner:5.1.1 >/dev/null
unset RTOK
for i in $(seq 1 30); do docker logs $R 2>&1 | grep -q 'declare successfully' && break; sleep 1; done

echo "== state database: one schema per environment, three roles"
docker exec -i $DB psql -q -U tfstate -d tfstate < state-admin.sql

echo "== Actions secrets (fake values)"
cs() { echo "postgres://$1:fake-lab-pass-$2@tfstate/tfstate?sslmode=disable"; }
sec() { # sec <repo> <name> <value>
  docker exec $C sh -c "jq -n --arg d '$3' '{data:\$d}' | curl -s -o /dev/null -X PUT -H 'Content-Type: application/json' \
    -H \"Authorization: token \$(cat /home/asha/.gitea-token)\" http://gitea:3000/api/v1/repos/allcsvideos/$1/actions/secrets/$2 -d @-"
}
sec allcsvideos-infra TF_STATE_PLAN "$(cs tf_plan plan)"           # read-only role, for every plan
sec allcsvideos-infra TF_STATE_STAGING "$(cs tf_staging staging)"  # writes the staging state only
sec infra-production TF_STATE_PROD "$(cs tf_prod prod)"            # writes the prod state only
tok=$(docker exec -u git $G gitea admin user generate-access-token --username rahul --token-name infra-read --scopes read:repository --raw)
sec infra-production INFRA_READ_TOKEN "$tok"; unset tok

echo "== infra-production repo (Rahul pushes the apply-prod workflow)"
docker cp "$LESSON/infra-production" $C:/tmp/prod-src
docker cp "$LESSON/allcsvideos-infra" $C:/tmp/infra-src
docker exec $C chmod -R a+rX /tmp/prod-src /tmp/infra-src
docker exec -u rahul $C bash -c 'cd ~ && git clone -q http://gitea:3000/allcsvideos/infra-production.git 2>/dev/null; cd infra-production \
  && cp -r /tmp/prod-src/. . && git add . && git commit -qm "apply-prod: apply a reviewed, saved prod plan" && git push -q origin HEAD:main'

echo
echo "lab up: open http://localhost:3000 (accounts in lab/accounts.txt)"
echo "shell as asha:  docker exec -it -u asha -w /home/asha tflab-team bash"
