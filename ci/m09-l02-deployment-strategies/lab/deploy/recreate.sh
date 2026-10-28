#!/bin/bash
# ~/deploy/recreate.sh <version> : strategy 0, RECREATE ("big bang")
# stop every old instance, then start the new version
set -euo pipefail
source ~/deploy/lib.sh
NEW=$1
log "stopping blue-1, blue-2, blue-3"
for n in blue-1 blue-2 blue-3; do stop_app $n; done
log "all stopped. starting $NEW"
for n in blue-1 blue-2 blue-3; do start_app $n $NEW; done
for n in blue-1 blue-2 blue-3; do wait_ready $n; done
log "all three ready on $NEW"
