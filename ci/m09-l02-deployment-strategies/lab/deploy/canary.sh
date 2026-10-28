#!/bin/bash
# ~/deploy/canary.sh <version> <percent> : strategy 3, CANARY
# send <percent> of requests to green; green grows from 1 to 3 instances as its share grows
set -euo pipefail
source ~/deploy/lib.sh
NEW=$1 PCT=$2
want=$(( PCT >= 50 ? 3 : 1 ))
for i in $(seq $want); do
  docker inspect green-$i >/dev/null 2>&1 && continue
  start_app green-$i $NEW; wait_ready green-$i; pool_add green green-$i
  log "green-$i ready on $NEW"
done
lb_render
if (( PCT == 100 )); then lb_route green; else lb_route blue green $PCT; fi
lb_reload
log "canary: $PCT% of requests now go to green ($NEW)"
