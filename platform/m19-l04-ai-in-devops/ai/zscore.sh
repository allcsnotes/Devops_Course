#!/bin/sh
# zscore.sh METRIC HH:MM: the z-score of a recorded metric at a moment, baseline = 30 min ending 5 min before
X=$1; T=$(date -d "$2" +%s)
curl -sG prometheus:9090/api/v1/query --data-urlencode time=$T --data-urlencode \
  "query=($X - avg_over_time($X[30m] offset 5m)) / stddev_over_time($X[30m] offset 5m)" | jq -c '.data.result[] | [.metric.service, .value[1]]'
