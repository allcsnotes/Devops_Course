# pq 'PromQL': run a query through the Prometheus HTTP API and print one line per series: labels, then value
pq() {
  curl -s localhost:9090/api/v1/query --data-urlencode "query=$1" | jq -r '.data.result[] |
    "\(.metric | to_entries | map("\(.key)=\(.value)") | join(" "))   \(.value[1])"'
}
# alerts: every active alert from Prometheus: name, severity, state, and since when (local time)
alerts() {
  curl -s localhost:9090/api/v1/alerts | jq -r '.data.alerts[] | "\(.labels.alertname)  severity=\(.labels.severity)  \(.state)  since \(.activeAt | sub("\\.[0-9]+"; "") | fromdate | localtime | strftime("%H:%M:%S"))"'
}
# slo: the SLO numbers right now, one per line (date first)
slo() {
  date +%H:%M:%S
  for r in job:slo_burn_rate:5m job:slo_burn_rate:1h job:slo_burn_rate:6h job:slo_error_budget:remaining_ratio30d; do
    printf '  %-40s %s\n' "$r" "$(curl -s localhost:9090/api/v1/query --data-urlencode "query=$r" | jq -r '.data.result[0].value[1][0:6]')"
  done
}
