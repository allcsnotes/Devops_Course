#!/usr/bin/env bash
# up.sh - the M09-L05 lab: Jenkins + gitlab-ci-local, all in Docker on the network cicd-lab, label course=devops.
#   cicd-gitea     gitea/gitea:28.1.0: Git server (repo allcsvideos/platform) + OCI registry gitea:3000; sends a push
#                  webhook to Jenkins. Web UI http://localhost:3000
#   cicd-docker    docker:29.5.3-dind (privileged): the ONLY Docker daemon builds use (TLS on docker:2376). The agent
#                  workspace and Asha's work folder are shared with it at the same paths.
#   jenkins        jenkins/jenkins:2.580.1-lts-jdk21 + 7 plugins, configured as code (casc.yaml). 0 executors.
#                  Web UI http://localhost:8080 (admin / fake-lab-admin-pass-123, a FAKE lab-only password)
#   jenkins-agent  agent linux-1 (jenkins/inbound-agent + docker CLI), connects to the controller over WebSocket
#   cicd-laptop    Asha's terminal: git, docker CLI (to cicd-docker), gitlab-ci-local 4.76.1
# Lab-only accounts, all FAKE: Gitea asha / fake-lab-pass-asha, priya / fake-lab-pass-priya, ci-bot (token only).
set -euo pipefail
cd "$(dirname "$0")"
L=(--label course=devops) N=cicd-lab ADMIN_PASSWORD=fake-lab-admin-pass-123
G=cicd-gitea C=cicd-laptop
docker network create "${L[@]}" $N >/dev/null
for v in gitea-data dind-certs dind-data agent-work asha-work jenkins-home jenkins-secrets; do docker volume create "${L[@]}" cicd-$v >/dev/null; done
echo "building the lab images (Jenkins installs its plugins: a few minutes the first time)"
docker build -q "${L[@]}" -t cicd-jenkins jenkins >/dev/null
docker build -q "${L[@]}" -t cicd-agent agent >/dev/null
docker build -q "${L[@]}" -t cicd-laptop laptop >/dev/null

docker run -d "${L[@]}" --name $G --hostname gitea --network $N --network-alias gitea -p 127.0.0.1:3000:3000 \
  -v cicd-gitea-data:/data -e USER_UID=1000 -e USER_GID=1000 \
  -e GITEA__database__DB_TYPE=sqlite3 -e GITEA__security__INSTALL_LOCK=true \
  -e GITEA__server__ROOT_URL=http://gitea:3000/ -e GITEA__server__DOMAIN=gitea -e GITEA__server__DISABLE_SSH=true \
  -e GITEA__service__DISABLE_REGISTRATION=true -e GITEA__repository__DEFAULT_BRANCH=main \
  -e GITEA__actions__ENABLED=false -e GITEA__packages__ENABLED=true \
  -e GITEA__security__ALLOWED_HOST_LIST=private gitea/gitea:28.1.0 >/dev/null
docker run -d "${L[@]}" --name cicd-docker --hostname docker --network $N --network-alias docker --privileged \
  -e DOCKER_TLS_CERTDIR=/certs -v cicd-dind-certs:/certs -v cicd-dind-data:/var/lib/docker \
  -v cicd-agent-work:/home/jenkins/agent -v cicd-asha-work:/home/asha/work \
  docker:29.5.3-dind --insecure-registry gitea:3000 >/dev/null
docker run -d --init "${L[@]}" --name $C --hostname laptop --network $N \
  -v cicd-dind-certs:/certs:ro -v cicd-asha-work:/home/asha/work cicd-laptop sleep infinity >/dev/null
docker exec -u root $C chown asha:asha /home/asha/work
until docker exec $G curl -sf http://localhost:3000/api/healthz >/dev/null 2>&1; do sleep 1; done
until docker exec cicd-docker docker info >/dev/null 2>&1; do sleep 1; done
echo "pulling the pinned build images into the lab's Docker daemon"
for i in python:3.12.15-slim python:3.13.16-slim postgres:18.6-alpine3.24 redis:8.10.2-alpine3.23 \
         hadolint/hadolint:v2.15.1 hadolint/hadolint:v2.15.1-debian docker:29.5.3 docker:29.5.3-dind \
         aquasec/trivy:0.76.0@sha256:2416d1f74045b57274df1a340eee6b510cacd73c66a6ccb8da092b117eb7d222; do
  docker exec cicd-docker docker pull -q "$i" >/dev/null
done

# ---- forge: lab accounts (FAKE passwords), tokens written straight to files (never printed), repo, webhook
gx(){ docker exec -u git $G gitea "$@"; }
gx admin user create --username asha --email asha@example.com --password fake-lab-pass-asha --admin --must-change-password=false --fullname Asha >/dev/null
gx admin user create --username priya --email priya@example.com --password fake-lab-pass-priya --must-change-password=false --fullname Priya >/dev/null
gx admin user create --username ci-bot --email ci-bot@example.com --password fake-lab-pass-ci-bot --must-change-password=false >/dev/null
gx admin user generate-access-token --username asha --token-name lab --scopes all --raw \
  | docker exec -i $C sh -c 'read -r t; printf "http://asha:%s@gitea:3000\n" "$t" > ~/.git-credentials; echo "$t" > ~/.gitea-token; chmod 600 ~/.git-credentials ~/.gitea-token'
docker exec -u root $C bash -c 'useradd -m -s /bin/bash priya'
gx admin user generate-access-token --username priya --token-name lab --scopes write:repository --raw \
  | docker exec -i -u priya $C sh -c 'read -r t; printf "http://priya:%s@gitea:3000\n" "$t" > ~/.git-credentials; chmod 600 ~/.git-credentials'
docker exec -u priya $C sh -c "git config --global user.name Priya && git config --global user.email priya@example.com && git config --global credential.helper store && git config --global init.defaultBranch main"
docker exec $C sh -c "git config --global user.name Asha && git config --global user.email asha@example.com && git config --global init.defaultBranch main && git config --global credential.helper store && git config --global advice.detachedHead false"
api(){ docker exec $C sh -c "curl -s -X $1 -H 'Content-Type: application/json' -H \"Authorization: token \$(cat ~/.gitea-token)\" http://gitea:3000/api/v1$2 ${3:+-d '$3'}"; }
api POST /orgs '{"username":"allcsvideos","full_name":"allcsvideos.com","visibility":"public"}' >/dev/null
api POST /orgs/allcsvideos/repos '{"name":"platform","description":"allcsvideos.com platform (lab copy)","default_branch":"main","private":false}' >/dev/null
t=$(api GET /orgs/allcsvideos/teams | docker exec -i $C jq '.[0].id'); api PUT /teams/$t/members/ci-bot >/dev/null
api PUT /repos/allcsvideos/platform/collaborators/priya '{"permission":"write"}' >/dev/null
# ci-bot's write:package token -> the Jenkins secret file (JCasC reads /run/secrets/REGISTRY_TOKEN) and Asha's
# gitlab-ci-local variables file (outside the repository). Never echoed.
ci=$(gx admin user generate-access-token --username ci-bot --token-name ci-push --scopes write:package --raw)
printf '%s' "$ci" | docker run --rm -i "${L[@]}" -v cicd-jenkins-secrets:/s alpine:3.23.6 sh -c 'umask 077; cat > /s/REGISTRY_TOKEN; chown 1000:1000 /s/REGISTRY_TOKEN'
printf '%s' "$ci" | docker exec -i $C sh -c 'umask 077; mkdir -p ~/.gitlab-ci-local; { echo "global:"; printf "  CI_REGISTRY_PASSWORD: \""; cat; printf "\"\n"; echo "  CI_REGISTRY: gitea:3000"; echo "  CI_REGISTRY_IMAGE: gitea:3000/allcsvideos"; echo "  CI_REGISTRY_USER: ci-bot"; } > ~/.gitlab-ci-local/variables.yml'
unset ci
# push webhook -> the Jenkins Git plugin: "something changed in this repository, check it now"
api POST /repos/allcsvideos/platform/hooks '{"type":"gitea","active":true,"events":["push"],"config":{"url":"http://jenkins:8080/git/notifyCommit?url=http://gitea:3000/allcsvideos/platform.git","content_type":"json"}}' >/dev/null
# gitlab-ci-local options: helper images pinned by digest (its defaults are :latest), privileged jobs for the
# docker:dind service, docker-volume caches, and a hosts entry so a job's own dind daemon can reach the registry
GIP=$(docker inspect -f '{{(index .NetworkSettings.Networks "cicd-lab").IPAddress}}' $G)
docker exec $C sh -c "cat > ~/.gitlab-ci-local/.env <<EOT
IGNORE_PREDEFINED_VARS=CI_REGISTRY,CI_REGISTRY_IMAGE
HELPER_IMAGE=firecow/gitlab-ci-local-util@sha256:1dc43cf4d8a4637a7da45eb95e14a97c750fbc9f1d45099bbd9f8ad6f0830778
WAIT_IMAGE=sumina46/wait-for-it@sha256:d7f14b742f5b83c1bc03c394487c2f672ca776cdc6b3dbc0922e9f9d05e30d39
PRIVILEGED=true
MOUNT_CACHE=true
EXTRA_HOST=gitea:$GIP
EOT"

# ---- Jenkins controller, then the agent linux-1
docker run -d "${L[@]}" --name jenkins --hostname jenkins --network $N --network-alias jenkins -p 127.0.0.1:8080:8080 \
  -e ADMIN_PASSWORD=$ADMIN_PASSWORD -v cicd-jenkins-home:/var/jenkins_home -v cicd-jenkins-secrets:/run/secrets:ro cicd-jenkins >/dev/null
echo -n "waiting for Jenkins"
for _ in $(seq 1 90); do
  docker exec jenkins curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/login 2>/dev/null | grep -q 200 && break
  echo -n .; sleep 2
done; echo
# the inbound agent's secret is derived by the controller for node linux-1 (read over the API, never printed)
sec=$(docker exec jenkins sh -c "curl -s -u admin:$ADMIN_PASSWORD http://localhost:8080/computer/linux-1/jenkins-agent.jnlp" | sed -n 's/.*<argument>\([0-9a-f]\{64\}\)<\/argument>.*/\1/p')
docker run -d --init "${L[@]}" --name jenkins-agent --hostname linux-1 --network $N \
  -v cicd-dind-certs:/certs:ro -v cicd-agent-work:/home/jenkins/agent \
  cicd-agent -url http://jenkins:8080/ -webSocket -workDir /home/jenkins/agent -secret "$sec" -name linux-1 >/dev/null
unset sec
echo "lab up. Gitea http://localhost:3000  Jenkins http://localhost:8080 (admin / $ADMIN_PASSWORD, FAKE)"
echo "Asha's terminal: docker exec -it -u asha -w /home/asha/work cicd-laptop bash"
