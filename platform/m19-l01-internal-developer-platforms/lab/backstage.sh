#!/usr/bin/env bash
# backstage.sh - runs the portal image allcsvideos-portal:1.0 on the lab network as http://backstage:7007
# (published on 127.0.0.1:7007 only). The bot token (FAKE / lab-only) is a mounted file, read at start, never printed.
set -euo pipefail
cd "$(dirname "$0")"
docker rm -f backstage >/dev/null 2>&1 || true
docker run -d --label course=devops --label lab=idp --name backstage --hostname backstage --network idp-net --network-alias backstage \
  -p 127.0.0.1:7007:7007 --memory 1536m -e NODE_OPTIONS=--max-old-space-size=1024 \
  -v "$PWD/../portal/app-config.lab.yaml":/app/app-config.lab.yaml:ro -v "$PWD/secrets/backstage-bot.token":/run/secrets/gitea-token:ro \
  allcsvideos-portal:1.0 sh -c 'GITEA_TOKEN=$(cat /run/secrets/gitea-token) exec node packages/backend --config app-config.yaml --config app-config.lab.yaml' >/dev/null
for i in $(seq 1 120); do curl -sf -o /dev/null http://localhost:7007/healthcheck && { echo "backstage up after ${i}x2s: http://backstage:7007"; exit 0; }; sleep 2; done
echo "backstage did not answer yet: docker logs backstage"; exit 1
