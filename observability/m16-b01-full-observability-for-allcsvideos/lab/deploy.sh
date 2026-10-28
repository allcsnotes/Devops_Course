#!/bin/bash
# deploy.sh copilot VERSION: roll Course Copilot to a version, then mark the deploy on every Grafana graph.
# Lab: version 1.1 = the same image with transcript search switched on (SEARCH_TRANSCRIPTS=1).
set -euo pipefail
svc=$1; ver=$2
export COPILOT_VERSION=$ver COPILOT_TRANSCRIPTS=$([ "$ver" = "1.1" ] && echo 1 || echo 0)
docker compose up -d --no-deps "$svc"
curl -s -X POST localhost:3000/api/annotations -H 'Content-Type: application/json' \
  -d "{\"tags\":[\"deploy\",\"$svc\"],\"text\":\"deploy $svc $ver\"}"; echo
