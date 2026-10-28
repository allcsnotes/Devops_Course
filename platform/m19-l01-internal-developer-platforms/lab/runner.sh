#!/usr/bin/env bash
# runner.sh - one Gitea Actions runner (gitea/runner:5.1.1, the same as the Module 8 lab). The registration token
# comes from Gitea's CLI and is never printed. Jobs run in gitea/runner-images:ubuntu-24.04-v26.10.01 on idp-net.
set -euo pipefail
cd "$(dirname "$0")"
tok=$(docker exec -u git gitea gitea actions generate-runner-token 2>&1 | tail -1)
docker volume create --label course=devops --label lab=idp idp-runner-data >/dev/null
docker run -d --label course=devops --label lab=idp --name gitea-runner --hostname runner-01 --network idp-net \
  -v /var/run/docker.sock:/var/run/docker.sock -v idp-runner-data:/data \
  -v "$PWD/runner-config.yaml":/config.yaml:ro -e CONFIG_FILE=/config.yaml \
  -e GITEA_INSTANCE_URL=http://gitea:3000/ -e GITEA_RUNNER_REGISTRATION_TOKEN="$tok" -e GITEA_RUNNER_NAME=runner-01 \
  gitea/runner:5.1.1 >/dev/null
unset tok
for i in $(seq 1 30); do docker logs gitea-runner 2>&1 | grep -q 'declare successfully' && break; sleep 1; done
docker logs gitea-runner 2>&1 | grep -v -i token | tail -3
