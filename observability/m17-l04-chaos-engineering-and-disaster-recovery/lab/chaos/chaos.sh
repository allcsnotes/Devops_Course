#!/usr/bin/env bash
# chaos.sh <experiment> : run ONE controlled chaos experiment from experiments/<experiment>.sh
#   1. check the steady state (the SLIs from lesson 1)   2. state the hypothesis   3. inject the fault
#   4. watch every 5 s, abort at once if the SLO is in danger   5. always roll back   6. verdict
set -euo pipefail
cd "$(dirname "$0")"
PROM=http://localhost:9090
GRAFANA=http://localhost:3000
ERR_MAX=0.0144   # abort: error ratio above 1.44 % = burning the 99.9 % SLO's budget 14.4x too fast (lesson 1's page)
P99_MAX=0.5      # abort: p99 latency above 500 ms, twice the 250 ms SLO
source "experiments/$1.sh"   # sets HYPOTHESIS and DURATION, defines inject and rollback

q()  { curl -s --get "$PROM/api/v1/query" --data-urlencode "query=$1" | jq -r '.data.result[0].value[1] // "0"'; }
now(){ date +%H:%M:%S; }
note(){ curl -s -o /dev/null -u admin:fake-admin-pass-123 -H 'Content-Type: application/json' \
          -d "{\"text\":\"chaos $1: $2\",\"tags\":[\"chaos\"]}" "$GRAFANA/api/annotations"; }   # FAKE lab password
sli(){ AV=$(q sli:availability:ratio_rate30s); P99=$(q sli:latency_p99:30s)
       ERR=$(awk -v a="$AV" 'BEGIN{printf "%.2f", (1-a)*100}'); MS=$(awk -v p="$P99" 'BEGIN{printf "%.0f", p*1000}'); }
bad(){ awk -v a="$AV" -v p="$P99" -v e="$ERR_MAX" -v m="$P99_MAX" 'BEGIN{exit !((1-a) > e || p > m)}'; }
slo(){ awk -v a="$AV" -v p="$P99" 'BEGIN{exit !((1-a) <= 0.001 && p <= 0.25)}'; }

sli; echo "$(now) steady state: errors ${ERR}%  p99 ${MS} ms"
slo || { echo "$(now) NOT steady: refusing to start"; exit 2; }
echo "$(now) hypothesis: $HYPOTHESIS"
WORST_E=0; WORST_P=0; ABORTED=no
done_(){ echo "$(now) rollback: $(rollback 2>&1 | tail -1)"; note "$1" rollback; }
trap 'done_ "$1"' EXIT                       # roll back on success, abort, error or Ctrl-C
echo "$(now) inject: $(inject 2>&1 | tail -1)"; note "$1" inject
for ((s = 5; s <= DURATION; s += 5)); do
  sleep 5; sli
  WORST_E=$(awk -v a="$WORST_E" -v b="$ERR" 'BEGIN{print (b > a) ? b : a}'); WORST_P=$(( MS > WORST_P ? MS : WORST_P ))
  if bad; then echo "$(now) ABORT: errors ${ERR}%  p99 ${MS} ms  (limit 1.44% / 500 ms)"; ABORTED=yes; break; fi
  echo "$(now)   +${s}s  errors ${ERR}%  p99 ${MS} ms"
done
trap - EXIT; done_ "$1"
for ((w = 0; w < 120; w += 5)); do sleep 5; sli; slo && break; done
echo "$(now) steady state back: errors ${ERR}%  p99 ${MS} ms"
if [[ $ABORTED == no ]] && awk -v e="$WORST_E" -v p="$WORST_P" 'BEGIN{exit !(e <= 0.1 && p <= 250)}'; then
  echo "RESULT: hypothesis held (worst: errors ${WORST_E}%, p99 ${WORST_P} ms)"
else
  echo "RESULT: hypothesis disproved (worst: errors ${WORST_E}%, p99 ${WORST_P} ms, aborted: $ABORTED)"
fi
