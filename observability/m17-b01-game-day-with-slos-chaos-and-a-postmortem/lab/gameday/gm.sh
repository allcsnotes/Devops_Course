#!/usr/bin/env bash
# gm.sh <scenario> : the game master runs ONE sealed scenario from sealed/<scenario>.sh (adapted from lesson 4's chaos.sh)
#   1. check the steady state        2. log the hypothesis (game master only)   3. inject, mark it (hidden board)
#   4. every 10 s: abort if the game day spent over 10 % of any budget, if the impact runs past 8 minutes,
#      or if anyone created the STOP file      5. when the IC logs "mitigated", end the fault: always roll back
set -euo pipefail
cd "$(dirname "$0")"
PROM=http://localhost:9090; GRAFANA=http://localhost:3000
CAP=0.10        # the policy: a game day may spend at most 10 % of any 30-day budget
MAX_S=480       # and no scenario runs longer than 8 minutes
source "sealed/$1.sh"   # sets HYPOTHESIS, defines inject and rollback

q()  { curl -s --get "$PROM/api/v1/query" --data-urlencode "query=$1" | jq -r '.data.result[0].value[1] // "0"'; }
pc() { awk -v v="$1" 'BEGIN{printf "%.2f%%", v*100}'; }
log(){ echo "$(date +%H:%M:%S) $*" | tee -a gm.log; }
ev() { echo "{\"epoch\":$(date +%s),\"scenario\":\"$1\",\"event\":\"$2\"}" >> ../incident/gm-events.log; }
note(){ curl -s -o /dev/null -X POST -H 'Content-Type: application/json' "$GRAFANA/api/annotations" \
          -d "{\"time\":$(date +%s)000,\"tags\":[\"gameday\"],\"text\":\"game day $1: $2\"}"; }
sli(){ E=$(q 'slo:sli_error:ratio_rate1m{slo="catalog-availability"}'); L=$(q 'slo:sli_error:ratio_rate1m{slo="catalog-latency"}')
       C=$(q 'slo:sli_error:ratio_rate1m{slo="copilot-availability"}'); }
steady(){ [[ $(q 'max(slo:burn_rate:1m) < bool 1') == 1 ]]; }

sli; log "steady state: course list errors $(pc $E), slow $(pc $L), Copilot errors $(pc $C)"
steady || { log "NOT steady: refusing to start"; exit 2; }
log "hypothesis: $HYPOTHESIS"
end_(){ log "rollback: $(rollback 2>&1 | tail -1)"; note "$1" "fault removed"; ev "$1" rollback; }
trap 'end_ "$1"' EXIT                        # roll back on mitigation, abort, an error or Ctrl-C
log "inject: $(inject 2>&1 | tail -1)"; note "$1" "fault injected"; ev "$1" inject; T0=$(date +%s)
while true; do
  sleep 10; sli; B=$(q 'max(slo:budget_used:ratio_gameday)'); el=$(( $(date +%s) - T0 ))
  if awk -v b="$B" -v c="$CAP" 'BEGIN{exit !(b > c)}'; then log "ABORT: the game day has used $(pc $B) of a budget (cap 10%)"; ev "$1" abort; break; fi
  if (( el > MAX_S )); then log "ABORT: $el s without mitigation (cap $MAX_S s)"; ev "$1" abort; break; fi
  if [[ -f STOP ]]; then log "ABORT: STOP called"; ev "$1" abort; break; fi
  if jq -e --argjson t $T0 'select(.epoch >= $t and (.msg | test("mitigated"; "i")))' ../incident/timeline.log >/dev/null 2>&1; then
    log "  +${el}s  the IC called it mitigated"; break; fi
  log "  +${el}s  course list errors $(pc $E), slow $(pc $L), Copilot errors $(pc $C) · budget used $(pc $B)"
done
trap - EXIT; end_ "$1"
for ((w = 0; w < 180; w += 10)); do sleep 10; steady && break; done
sli; log "steady state back: course list errors $(pc $E), slow $(pc $L), Copilot errors $(pc $C)"
log "budget used by the game day so far: course list $(pc $(q 'slo:budget_used:ratio_gameday{slo="catalog-availability"}')), slow $(pc $(q 'slo:budget_used:ratio_gameday{slo="catalog-latency"}')), Copilot $(pc $(q 'slo:budget_used:ratio_gameday{slo="copilot-availability"}'))"
