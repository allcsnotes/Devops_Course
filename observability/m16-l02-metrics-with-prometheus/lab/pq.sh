# pq 'PromQL': run a query through the Prometheus HTTP API and print one line per series: labels, then value(s)
pq() {
  curl -s localhost:9090/api/v1/query --data-urlencode "query=$1" | jq -r '.data.result[] |
    "\(.metric | to_entries | map("\(.key)=\(.value)") | join(" "))   \(.value[1] // (.values | map(.[1]) | join(" ")))"'
}
