#!/bin/bash
# ~/deploy/bluegreen.sh <version> : strategy 2, BLUE-GREEN (step 1 of 2)
# start a full green stack next to blue and smoke test it directly; users still go to blue
set -euo pipefail
source ~/deploy/lib.sh
NEW=$1
pool_clear green
log "starting green: 3 instances of $NEW"
for n in green-1 green-2 green-3; do start_app $n $NEW; pool_add green $n; done
for n in green-1 green-2 green-3; do wait_ready $n; done
log "green is up: 3 instances of $NEW"
for n in green-1 green-2 green-3; do           # smoke test: a real question, straight to each instance
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://$(ip_of $n):8000/ask?q=docker")
  log "smoke test $n /ask: $code"
  [[ $code == 200 ]] || { log "smoke test failed: green stays out of service"; exit 1; }
done
lb_render; lb_reload
log "green passed. users are still on blue. switch with: ./switch.sh green"
