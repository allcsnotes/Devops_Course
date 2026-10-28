#!/bin/bash
# ~/deploy/rolling-naive.sh <version> : the PITFALL version of rolling.sh - no drain, no readiness check.
# Each instance is stopped while nginx still sends it traffic, and the next one is replaced right away.
set -euo pipefail
source ~/deploy/lib.sh
NEW=$1
for n in blue-1 blue-2 blue-3; do
  stop_app $n
  start_app $n $NEW
  log "$n: replaced with $NEW (not checked)"
done
log "rollout complete"
