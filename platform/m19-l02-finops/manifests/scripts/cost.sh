#!/bin/bash
# cost.sh <aggregate> [window]   OpenCost allocation API -> cost per hour and a 730-hour month, per namespace / label
#   prices: lab custom pricing from the AWS t3.medium list price (see opencost-values.yaml); idle cost not included
set -euo pipefail
AGG=$1; W=${2:-30m}; OC=${OC:-http://localhost:9003}
curl -s "$OC/allocation/compute?window=$W&aggregate=$AGG&accumulate=true" | jq -r '
  .data[0] | to_entries | map(.value) | map(select(.name != "__idle__")) | sort_by(-.totalCost) |
  (["NAME", "CPU-REQ", "CPU-USED", "MEM-REQ", "MEM-USED", "$/HOUR", "$/MONTH", "EFFICIENCY"] | @tsv),
  (.[] | (.minutes / 60) as $h | [.name,
     (.cpuCoreRequestAverage | . * 100 | round / 100 | tostring),
     (.cpuCoreUsageAverage | . * 100 | round / 100 | tostring),
     ((.ramByteRequestAverage / 1073741824) * 100 | round / 100 | tostring) + "Gi",
     ((.ramByteUsageAverage / 1073741824) * 100 | round / 100 | tostring) + "Gi",
     (.totalCost / $h | . * 10000 | round / 10000 | tostring),
     (.totalCost / $h * 730 | . * 100 | round / 100 | tostring),
     ((.totalEfficiency * 100 | round | tostring) + "%")] | @tsv)' | column -t -s $'\t'
