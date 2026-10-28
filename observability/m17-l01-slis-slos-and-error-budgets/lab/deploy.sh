#!/bin/sh
# deploy.sh VERSION [FAULT_RATE]: roll the catalog API to VERSION, then mark the deploy on the dashboards.
# GRAFANA_TOKEN: a token of the deploy-bot service account (Editor), kept outside Git like a CI secret.
set -eu
VERSION=$1; FAULT=${2:-0}
API_VERSION=$VERSION API_FAULT_RATE=$FAULT docker compose up -d --no-deps api
curl -s -X POST localhost:3000/api/annotations \
  -H "Authorization: Bearer $GRAFANA_TOKEN" -H "Content-Type: application/json" \
  -d "{\"tags\": [\"deploy\", \"api\"], \"text\": \"api $VERSION deployed\"}"
echo
