# source tools.sh (from this folder): helpers for the alerting lab
#   pq 'PromQL'   query Prometheus (localhost:9090), one line per series
#   promtool ...  Prometheus's promtool, run inside the prometheus container (files are under /etc/prometheus)
#   amtool ...    Alertmanager's amtool, run inside the alertmanager container, talking to the running Alertmanager
pq() {
  curl -s localhost:9090/api/v1/query --data-urlencode "query=$1" | jq -r '.data.result[] |
    "\(.metric | to_entries | map("\(.key)=\(.value)") | join(" "))   \(.value[1] // (.values | map(.[1]) | join(" ")))"'
}
promtool() { docker compose exec -T -w /etc/prometheus prometheus promtool "$@"; }
amtool() { docker compose exec -T -w /etc/alertmanager alertmanager amtool --alertmanager.url=http://localhost:9093 "$@"; }
