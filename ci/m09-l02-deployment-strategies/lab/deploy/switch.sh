#!/bin/bash
# ~/deploy/switch.sh blue|green : strategy 2, BLUE-GREEN (step 2 of 2)
# point the load balancer at the other pool. Rollback is the same command with the other colour.
set -euo pipefail
source ~/deploy/lib.sh
t0=$(date +%s%3N)
lb_route "$1"; lb_reload
log "all traffic now goes to $1 (switch took $(( $(date +%s%3N) - t0 )) ms)"
