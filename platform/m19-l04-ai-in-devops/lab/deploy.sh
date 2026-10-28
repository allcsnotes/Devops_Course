#!/bin/bash
# deploy.sh SERVICE VERSION [BY]: roll a service's replicas one by one to an image tag (also used to roll back), log it.
#   SERVICE: catalog-api (api-1, api-2) or storefront-bff (bff-1, bff-2)
set -euo pipefail
cd "$(dirname "$0")"
svc=$1; v=$2; by=${3:-ci}; t0=$(date +%s)
case $svc in
  catalog-api) var=API_VERSION; reps="api-1 api-2" ;;
  storefront-bff) var=EDGE_VERSION; reps="bff-1 bff-2" ;;
  *) echo "unknown service $svc"; exit 2 ;;
esac
echo "$(date +%H:%M:%S) deploy $svc $v by $by: start"
for r in $reps; do env $var=$v docker compose up -d --no-deps --wait $r 2>&1 | grep -v Waiting || true; done
echo "{\"start\":$t0,\"epoch\":$(date +%s),\"service\":\"$svc\",\"version\":\"$v\",\"by\":\"$by\"}" >> incident/deploys.log
echo "$(date +%H:%M:%S) deploy $svc $v by $by: done"
