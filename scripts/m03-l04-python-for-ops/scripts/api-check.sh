#!/usr/bin/env bash
# api-check.sh: is the allcsvideos API healthy?
set -euo pipefail

if curl -s --max-time 3 http://api-01:8080/health | grep -q '"status": "ok"'; then
  echo "OK    api is healthy"
else
  echo "WARN  api is unhealthy"
  exit 1
fi
