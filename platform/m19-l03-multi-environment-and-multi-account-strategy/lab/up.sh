#!/usr/bin/env bash
# up.sh: start the M19-L03 lab on your laptop. Everything runs in Docker, is named lab-* and labelled
# course=devops, lesson=m19-l03. No cloud and no cloud credentials anywhere; every password and token is lab-only.
#
#   lab-net              the lab's Docker network
#   lab-gitea            gitea/gitea:28.1.0 (Git, web UI, API, Gitea Actions)    http://localhost:3000
#   lab-registry         registry:3.1.2, the shared image registry (stand-in for ECR in a shared account), localhost:5001
#   lab-laptop           the team machine: users asha, priya, rahul; terraform 1.16.6, kustomize v5.8.3, tea 0.16.0
#   lab-build            the CI build box "build-01": builds each image ONCE and pushes it (uses your Docker)
#   lab-runner           gitea/runner:5.1.1, runs the promotion-check job
#   lab-agent-<env>      lab stand-in for Argo CD, one per "account" (dev, staging, prod)
#
# (Port 5001, not 5000, because macOS uses 5000 for AirPlay.)
set -euo pipefail
cd "$(dirname "$0")"
L=(--label course=devops --label lesson=m19-l03)
N=lab-net
cap(){ printf '%s%s' "$(printf %s "${1:0:1}" | tr a-z A-Z)" "${1:1}"; }   # asha -> Asha (works in macOS bash 3.2)

echo "1/6 network, Gitea, registry, images"
docker network inspect $N >/dev/null 2>&1 || docker network create "${L[@]}" $N >/dev/null
docker volume create "${L[@]}" lab-gitea-data >/dev/null
docker run -d "${L[@]}" --name lab-gitea --hostname gitea --network $N --network-alias gitea -p 127.0.0.1:3000:3000 \
  -v lab-gitea-data:/data -e USER_UID=1000 -e USER_GID=1000 \
  -e GITEA__database__DB_TYPE=sqlite3 -e GITEA__security__INSTALL_LOCK=true \
  -e GITEA__server__ROOT_URL=http://gitea:3000/ -e GITEA__server__DOMAIN=gitea -e GITEA__server__DISABLE_SSH=true \
  -e GITEA__service__DISABLE_REGISTRATION=true -e GITEA__repository__DEFAULT_BRANCH=main \
  -e GITEA__actions__ENABLED=true --memory 512m gitea/gitea:28.1.0 >/dev/null
docker run -d "${L[@]}" --name lab-registry --hostname registry --network $N --network-alias registry.lab \
  -p 127.0.0.1:5001:5000 -e REGISTRY_STORAGE_DELETE_ENABLED=true --memory 128m registry:3.1.2 >/dev/null
docker build -q "${L[@]}" -t lab-laptop laptop >/dev/null
docker build -q "${L[@]}" -t lab-agent agent >/dev/null
docker run -d --init "${L[@]}" --name lab-laptop --hostname laptop --network $N --memory 1g lab-laptop >/dev/null
for u in asha priya rahul; do
  docker exec -u $u -e HOME=/home/$u lab-laptop sh -c "git config --global user.name '$(cap $u)' && git config --global user.email $u@example.com \
    && git config --global init.defaultBranch main && git config --global credential.helper store && git config --global advice.detachedHead false"
done
docker run -d --init "${L[@]}" --name lab-build --hostname build-01 --network $N --memory 256m \
  -v /var/run/docker.sock:/var/run/docker.sock -e TZ=IST-5:30 lab-agent sleep infinity >/dev/null
docker exec lab-build sh -c 'echo "export PS1=\"ci@build-01:\\w\\$ \"" >> /root/.bashrc; git config --global --add safe.directory "*"; mkdir -p /work'
until docker exec lab-gitea curl -sf http://localhost:3000/api/healthz >/dev/null 2>&1; do sleep 1; done

echo "2/6 Gitea users, tokens, organisation and teams (see accounts.txt)"
gx(){ docker exec -u git lab-gitea gitea "$@"; }
gx admin user create --username asha --email asha@example.com --password fake-lab-pass-asha --admin --must-change-password=false --fullname Asha >/dev/null
for u in priya rahul ci-bot deploy-bot; do
  gx admin user create --username $u --email $u@example.com --password fake-lab-pass-$u --must-change-password=false --fullname "$(cap $u)" >/dev/null
done
mkdir -p secrets; chmod 700 secrets
for u in asha priya rahul; do   # each person's token goes straight into their home on the lab laptop, never printed
  tok=$(gx admin user generate-access-token --username $u --token-name lab --scopes all --raw)
  docker exec -u $u -e HOME=/home/$u lab-laptop sh -c "printf 'http://%s:%s@gitea:3000\n' '$u' '$tok' > ~/.git-credentials && echo '$tok' > ~/.gitea-token \
    && chmod 600 ~/.git-credentials ~/.gitea-token && tea login add --name lab --url http://gitea:3000 --token '$tok' >/dev/null"
done
gx admin user generate-access-token --username ci-bot --token-name ci --scopes write:repository --raw > secrets/ci-bot.token
gx admin user generate-access-token --username deploy-bot --token-name agents --scopes read:repository --raw > secrets/deploy-bot.token
printf 'http://deploy-bot:%s@gitea:3000/allcsvideos/allcsvideos-deploy.git' "$(cat secrets/deploy-bot.token)" > secrets/repo-url
printf 'http://ci-bot:%s@gitea:3000/allcsvideos/allcsvideos-deploy.git' "$(cat secrets/ci-bot.token)" > secrets/ci-url
chmod 600 secrets/*
api(){ local u=$1 m=$2 p=$3 d=${4:-}
  docker exec -u "$u" -e HOME=/home/$u lab-laptop sh -c "curl -s -X $m -H 'Content-Type: application/json' -H \"Authorization: token \$(cat ~/.gitea-token)\" http://gitea:3000/api/v1$p ${d:+-d '$d'}"; }
api asha POST /orgs '{"username":"allcsvideos","full_name":"allcsvideos.com","visibility":"private"}' >/dev/null
team(){ api asha POST /orgs/allcsvideos/teams "{\"name\":\"$1\",\"permission\":\"$2\",\"units\":[\"repo.code\",\"repo.issues\",\"repo.pulls\",\"repo.actions\"],\"includes_all_repositories\":true}" | docker exec -i lab-laptop jq .id; }
td=$(team devs write); tr=$(team releasers write); tw=$(team readers read)
for u in priya ci-bot; do api asha PUT /teams/$td/members/$u >/dev/null; done
api asha PUT /teams/$tr/members/rahul >/dev/null
api asha PUT /teams/$tw/members/deploy-bot >/dev/null

echo "3/6 the app repo (api 1.8.0) in build-01, built and pushed once"
docker cp ../api lab-build:/work/allcsvideos-api
docker exec -w /work/allcsvideos-api lab-build sh -c 'git init -q -b main && git config user.name Priya && git config user.email priya@example.com \
  && git add . && git commit -qm "api 1.8.0" && git tag v1.8.0'
D=$(docker exec -w /work/allcsvideos-api lab-build build-image 1.8.0 | sed -n 's/^digest //p')
echo "   api 1.8.0 = $D"

echo "4/6 Asha's repos: allcsvideos-infra (local) and allcsvideos-deploy (pushed to Gitea)"
docker cp ../infra lab-laptop:/home/asha/allcsvideos-infra
docker cp ../deploy lab-laptop:/home/asha/allcsvideos-deploy
docker exec lab-laptop chown -R asha:asha /home/asha/allcsvideos-infra /home/asha/allcsvideos-deploy
api asha POST /orgs/allcsvideos/repos '{"name":"allcsvideos-deploy","private":true,"default_branch":"main"}' >/dev/null
docker exec -u asha -e HOME=/home/asha -w /home/asha/allcsvideos-deploy lab-laptop sh -c "
  for e in dev staging prod; do (cd envs/\$e && kustomize edit set image allcsvideos/api=localhost:5001/allcsvideos/api@$D); done
  git init -q && git add . && git commit -qm 'deploy repo: api 1.8.0 in dev, staging and prod'
  git remote add origin http://gitea:3000/allcsvideos/allcsvideos-deploy.git && git push -q -u origin main"
docker exec -i lab-build sh -c "git clone -q \"\$(cat)\" /work/allcsvideos-deploy && cd /work/allcsvideos-deploy \
  && git config user.name ci-bot && git config user.email ci-bot@example.com" < secrets/ci-url

echo "5/6 branch protection on main, and the Actions runner"
api asha POST /repos/allcsvideos/allcsvideos-deploy/branch_protections \
  '{"rule_name":"main","enable_push":false,"unprotected_file_patterns":"envs/dev/**","required_approvals":1,"enable_approvals_whitelist":true,"approvals_whitelist_teams":["releasers"],"dismiss_stale_approvals":true,"block_on_rejected_reviews":true,"enable_status_check":true,"status_check_contexts":["promotion-check / check (pull_request)"]}' >/dev/null
tok=$(docker exec -u git lab-gitea gitea actions generate-runner-token 2>&1 | tail -1)
docker volume create "${L[@]}" lab-runner-data >/dev/null
docker run -d "${L[@]}" --name lab-runner --hostname runner-01 --network $N \
  -v /var/run/docker.sock:/var/run/docker.sock -v lab-runner-data:/data \
  -v "$PWD/runner/config.yaml:/config.yaml:ro" -e CONFIG_FILE=/config.yaml \
  -e GITEA_INSTANCE_URL=http://gitea:3000/ -e GITEA_RUNNER_REGISTRATION_TOKEN="$tok" -e GITEA_RUNNER_NAME=runner-01 \
  --memory 256m gitea/runner:5.1.1 >/dev/null
unset tok

echo "6/6 one GitOps agent per account (read-only deploy-bot token)"
for e in dev staging prod; do
  docker run -d "${L[@]}" --name lab-agent-$e --hostname argocd-$e --network $N \
    -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD/secrets/repo-url:/run/secrets/repo-url:ro" \
    -e ENV=$e --memory 128m lab-agent >/dev/null
done
echo "lab up: Gitea http://localhost:3000 (users in accounts.txt). Shells: ./shell.sh asha|priya|rahul|ci"
