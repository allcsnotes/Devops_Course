#!/bin/bash
# deploy.sh VERSION: roll the catalog API to an image tag (also used to roll back), log it, mark it in Grafana.
set -euo pipefail
cd "$(dirname "$0")"
v=$1; by=${2:-ci}; t0=$(date +%s)
echo "$(date +%H:%M:%S) deploy catalog-api $v by $by: start"
API_VERSION=$v docker compose up -d --wait api 2>&1 | grep -v -e '^ *Container incident-db' -e Waiting || true
now=$(date +%s)
echo "{\"start\":$t0,\"epoch\":$now,\"version\":\"$v\",\"by\":\"$by\"}" >> incident/deploys.log
curl -s -o /dev/null -X POST -H 'Content-Type: application/json' http://127.0.0.1:3000/api/annotations \
  -d "{\"time\":${t0}000,\"tags\":[\"deploy\"],\"text\":\"deploy catalog-api $v ($by)\"}"
echo "$(date +%H:%M:%S) deploy catalog-api $v by $by: done, $(curl -s 127.0.0.1:8080/healthz)"
