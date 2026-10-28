#!/usr/bin/env bash
# up.sh - starts the M19-L01 lab: a Docker network and Gitea (Git + web UI + API + Gitea Actions).
#   idp-net   the lab network
#   gitea     gitea/gitea:28.1.0 on http://gitea:3000 (published on 127.0.0.1:3000 only)
# Your browser and git reach it as http://gitea:3000 thanks to the hosts entry from the README (step 1).
# Every password and token in this lab is FAKE / lab-only.
set -euo pipefail
N=idp-net
docker network inspect $N >/dev/null 2>&1 || docker network create --label course=devops --label lab=idp $N >/dev/null
docker volume create --label course=devops --label lab=idp idp-gitea-data >/dev/null
docker run -d --label course=devops --label lab=idp --name gitea --hostname gitea --network $N --network-alias gitea \
  -p 127.0.0.1:3000:3000 -v idp-gitea-data:/data -e USER_UID=1000 -e USER_GID=1000 \
  -e GITEA__database__DB_TYPE=sqlite3 -e GITEA__security__INSTALL_LOCK=true \
  -e GITEA__server__ROOT_URL=http://gitea:3000/ -e GITEA__server__DOMAIN=gitea -e GITEA__server__DISABLE_SSH=true \
  -e GITEA__service__DISABLE_REGISTRATION=true -e GITEA__repository__DEFAULT_BRANCH=main \
  -e GITEA__actions__ENABLED=true --memory 512m gitea/gitea:28.1.0 >/dev/null
until docker exec gitea curl -sf http://localhost:3000/api/healthz >/dev/null 2>&1; do sleep 1; done
echo "gitea up: http://gitea:3000"
