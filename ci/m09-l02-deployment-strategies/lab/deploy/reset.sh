#!/bin/bash
# ~/deploy/reset.sh <version> : lab only - put prod back to a known start: blue-1..3 on <version>, no green, LB on blue
source ~/deploy/lib.sh
docker rm -f blue-1 blue-2 blue-3 green-1 green-2 green-3 >/dev/null 2>&1
pool_clear blue; pool_clear green
for n in blue-1 blue-2 blue-3; do start_app $n $1; pool_add blue $n; done
for n in blue-1 blue-2 blue-3; do wait_ready $n; done
lb_render; lb_route blue; lb_reload
log "reset: blue-1..3 on $1, all traffic to blue"
