#!/bin/bash
# ~/deploy/rolling.sh <version> : strategy 1, ROLLING UPDATE
# one instance at a time: drain it, replace it, wait until it is ready, put it back
set -euo pipefail
source ~/deploy/lib.sh
NEW=$1
for n in blue-1 blue-2 blue-3; do
  log "$n: drain (marked down, nginx reload)"
  pool_set blue $n down; lb_render; lb_reload
  sleep 2                                  # let in-flight requests finish
  stop_app $n
  start_app $n $NEW
  wait_ready $n || { log "$n never got ready: rollout stopped"; exit 1; }
  pool_set blue $n; lb_render; lb_reload
  log "$n: ready on $NEW, back in the pool"
done
log "rollout complete: 3 of 3 on $NEW"
