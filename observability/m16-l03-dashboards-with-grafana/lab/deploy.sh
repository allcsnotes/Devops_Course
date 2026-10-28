#!/bin/sh
# deploy.sh VERSION [SORT]: roll both API copies to VERSION, then mark the deploy on the dashboards.
# GRAFANA_TOKEN: a token of the deploy-bot service account (Editor), kept outside Git like a CI secret.
set -eu
VERSION=$1; SORT=${2:-id}
API_VERSION=$VERSION API_DEFAULT_SORT=$SORT docker compose up -d --no-deps api-1 api-2
curl -s -X POST localhost:3000/api/annotations \
  -H "Authorization: Bearer $GRAFANA_TOKEN" -H "Content-Type: application/json" \
  -d "{\"tags\": [\"deploy\", \"api\"], \"text\": \"api $VERSION deployed (sort=$SORT)\"}"
echo
