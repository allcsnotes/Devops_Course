#!/bin/bash
# pq.sh 'PromQL': ask Prometheus, print one line per series: its labels, then the value (4 significant digits)
curl -s localhost:9090/api/v1/query --data-urlencode "query=$1" | jq -r '.data.result[] |
  "\(.metric | del(.__name__) | to_entries | map("\(.key)=\(.value)") | join(" "))   \(.value[1] | tonumber | . * 10000 | round / 10000)"'
