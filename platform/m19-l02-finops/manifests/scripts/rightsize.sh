#!/bin/bash
# rightsize.sh <namespace> [window]   requests vs REAL usage per Deployment, from Prometheus (cAdvisor + OpenCost metrics)
#   suggestion: CPU = p95 usage x 1.3 (rounded up to 10m, at least 10m); memory = peak working set x 1.5 (at least 64Mi)
set -euo pipefail
NS=$1; W=${2:-30m}; PROM=${PROM:-http://localhost:9090}
q(){ curl -s "$PROM/api/v1/query" --data-urlencode "query=$1" | jq -r '.data.result[] | "\(.metric.container) \(.value[1])"'; }
declare -A REQC REQM P95 PEAK
while read -r c v; do REQC[$c]=$v; done < <(q "max by (container) (kube_pod_container_resource_requests{namespace=\"$NS\",resource=\"cpu\"})")
while read -r c v; do REQM[$c]=$v; done < <(q "max by (container) (kube_pod_container_resource_requests{namespace=\"$NS\",resource=\"memory\"})")
while read -r c v; do P95[$c]=$v; done < <(q "max by (container) (quantile_over_time(0.95, rate(container_cpu_usage_seconds_total{namespace=\"$NS\",container!=\"\"}[1m])[$W:15s]))")
while read -r c v; do PEAK[$c]=$v; done < <(q "max by (container) (max_over_time(container_memory_working_set_bytes{namespace=\"$NS\",container!=\"\"}[$W]))")
printf '%-11s %9s %9s %6s %10s %10s %6s   %s\n' DEPLOYMENT CPU-REQ CPU-P95 USED MEM-REQ MEM-PEAK USED SUGGEST
for c in $(printf '%s\n' "${!REQC[@]}" | sort); do
  awk -v n=$c -v rc=${REQC[$c]} -v rm=${REQM[$c]} -v u=${P95[$c]:-0} -v m=${PEAK[$c]:-0} 'BEGIN {
    sc = int(u * 1.3 * 100 + 0.999) * 10; if (sc < 10) sc = 10
    sm = int(m * 1.5 / 1048576 / 16 + 0.999) * 16; if (sm < 64) sm = 64
    printf "%-11s %8dm %8dm %5.0f%% %8dMi %8dMi %5.0f%%   cpu=%dm memory=%dMi\n", n, rc*1000, u*1000+0.5, 100*u/rc, rm/1048576, m/1048576+0.5, 100*m/rm, sc, sm }'
done
