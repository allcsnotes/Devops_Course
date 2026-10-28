#!/bin/bash
# deploy.sh VERSION [BY]: roll both API replicas to an image tag, one at a time (also used to roll back),
# log it for the timeline, and mark it on the Grafana dashboard.
set -euo pipefail
cd "$(dirname "$0")"
v=$1; by=${2:-ci}; t0=$(date +%s)
echo "$(date +%H:%M:%S) deploy catalog-api $v by $by: start"
for r in api1 api2; do                       # one replica at a time: the other keeps serving
  API_VERSION=$v docker compose up -d --no-deps --wait $r 2>&1 | grep -E "Container .*(Started|Healthy)$" | tail -1 || true
done
echo "{\"start\":$t0,\"epoch\":$(date +%s),\"version\":\"$v\",\"by\":\"$by\"}" >> incident/deploys.log
curl -s -o /dev/null -X POST -H 'Content-Type: application/json' http://127.0.0.1:3000/api/annotations \
  -d "{\"time\":${t0}000,\"tags\":[\"deploy\"],\"text\":\"deploy catalog-api $v ($by)\"}"
echo "$(date +%H:%M:%S) deploy catalog-api $v by $by: done, $(docker compose exec -T api1 python -c 'import urllib.request;print(urllib.request.urlopen("http://127.0.0.1:8080/healthz").read().decode().strip())')"
