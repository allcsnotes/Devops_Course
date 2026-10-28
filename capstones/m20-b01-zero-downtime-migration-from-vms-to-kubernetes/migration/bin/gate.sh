#!/bin/bash
# gate.sh [SECONDS]: the SLO gate, from what the students saw (k6 counters in Prometheus) over the last SECONDS (60).
# SLOs (M20-L01): 99.9 % of requests succeed, 99 % answer within 250 ms. Checked for the Kubernetes pool on its own
# and for all students. Any breach: exit 1.
set -uo pipefail
W=${1:-60}; PROM=http://10.0.201.30:9090/api/v1/query
q(){ curl -s --get $PROM --data-urlencode "query=round(sum(increase($1[${W}s])) or vector(0))" | jq -r '.data.result[0].value[1]'; }
fail=0
printf '%-22s %9s %8s %12s\n' "SLO gate, last ${W} s" requests errors "over 250 ms"
for pool in k8s all; do
  sel=$([ $pool = all ] && echo '' || echo "pool=\"$pool\"")
  n=$(q "k6_allcs_reqs_total{$sel}"); e=$(q "k6_allcs_reqs_total{${sel:+$sel,}ok=\"false\"}"); s=$(q "k6_allcs_slow_total{$sel}")
  v=$(awk -v n=$n -v e=$e -v s=$s 'BEGIN{ if (n==0) print "no traffic"; else if (e/n>0.001 || s/n>0.01) print "BREACH"; else print "ok" }')
  [ "$v" = BREACH ] && fail=1
  printf '  %-20s %9s %8s %12s   %s\n' "$([ $pool = all ] && echo 'all students' || echo 'Kubernetes pool')" $n $e $s "$v"
done
if [ $fail = 0 ]; then echo "PASS (errors <= 0.1 %, slow <= 1 %)"; else echo "FAIL"; fi
exit $fail
