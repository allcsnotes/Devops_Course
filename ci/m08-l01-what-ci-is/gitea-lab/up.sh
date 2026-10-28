#!/usr/bin/env bash
# up.sh - OPTIONAL local CI lab for Module 8/9: Gitea (Git server + web UI + Gitea Actions) and a Gitea runner,
# all in Docker. Use it if you want to practise CI without a GitHub account or offline. Everything it creates
# carries the label course=devops and is removed by down.sh.
#
#   gitea         gitea/gitea:28.1.0   web UI on http://localhost:3000, Actions switched on
#   gitea-runner  gitea/runner:5.1.1   (formerly "act_runner") starts one fresh job container per job from
#                 gitea/runner-images:ubuntu-24.04-v26.10.01 (the label ubuntu-latest, see runner-config.yaml)
#
# It also creates a lab-only admin user and an empty repository you can push to:
#   user ci-admin, password change-me-123  (a FAKE lab password - fine here, never reuse it anywhere real)
#   repo http://localhost:3000/ci-admin/allcsvideos-ops
set -euo pipefail
cd "$(dirname "$0")"
NET=ci-lab
ADMIN=ci-admin
PASS=change-me-123
L=(--label course=devops)

docker network create "${L[@]}" "$NET" >/dev/null
docker volume create "${L[@]}" gitea-data >/dev/null
docker run -d "${L[@]}" --name gitea --hostname gitea --network "$NET" --network-alias gitea \
  -p 127.0.0.1:3000:3000 -v gitea-data:/data \
  -e USER_UID=1000 -e USER_GID=1000 \
  -e GITEA__database__DB_TYPE=sqlite3 \
  -e GITEA__security__INSTALL_LOCK=true \
  -e GITEA__server__ROOT_URL=http://gitea:3000/ -e GITEA__server__DOMAIN=gitea -e GITEA__server__DISABLE_SSH=true \
  -e GITEA__service__DISABLE_REGISTRATION=true \
  -e GITEA__repository__DEFAULT_BRANCH=main \
  -e GITEA__actions__ENABLED=true \
  gitea/gitea:28.1.0 >/dev/null
echo -n "waiting for Gitea"
until docker exec gitea curl -sf http://localhost:3000/api/healthz >/dev/null 2>&1; do echo -n .; sleep 1; done; echo

# the lab admin (Gitea's own CLI, run as the user git inside the container)
docker exec -u git gitea gitea admin user create --username "$ADMIN" --email "$ADMIN@example.com" \
  --password "$PASS" --admin --must-change-password=false >/dev/null
# an empty repository to push to
curl -sf -u "$ADMIN:$PASS" -H 'Content-Type: application/json' -X POST http://localhost:3000/api/v1/user/repos \
  -d '{"name":"allcsvideos-ops","default_branch":"main"}' >/dev/null

# the runner: a registration token from Gitea's CLI (a secret: passed straight in, never printed)
tok=$(docker exec -u git gitea gitea actions generate-runner-token | tail -1)
docker volume create "${L[@]}" gitea-runner-data >/dev/null
docker run -d "${L[@]}" --name gitea-runner --hostname runner-01 --network "$NET" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v gitea-runner-data:/data \
  -v "$PWD/runner-config.yaml:/config.yaml:ro" \
  -e CONFIG_FILE=/config.yaml \
  -e GITEA_INSTANCE_URL=http://gitea:3000/ \
  -e GITEA_RUNNER_REGISTRATION_TOKEN="$tok" \
  -e GITEA_RUNNER_NAME=runner-01 \
  gitea/runner:5.1.1 >/dev/null
unset tok
for _ in $(seq 1 30); do docker logs gitea-runner 2>&1 | grep -q 'declare successfully' && break; sleep 1; done
docker logs gitea-runner 2>&1 | grep -v -i token | tail -3
echo
echo "Gitea:  http://localhost:3000   (user $ADMIN, lab password $PASS)"
echo "Push:   git remote add gitea http://localhost:3000/$ADMIN/allcsvideos-ops.git && git push -u gitea main"
