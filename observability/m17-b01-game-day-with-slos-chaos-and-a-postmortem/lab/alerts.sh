#!/bin/bash
# alerts.sh: every active alert in Prometheus: name, its slo, severity, state, and since when
curl -s localhost:9090/api/v1/alerts | jq -r '.data.alerts[] | "\(.labels.alertname) \(.labels.slo // "")  severity=\(.labels.severity)  \(.state)  since \(.activeAt | sub("\\.[0-9]+"; "") | fromdate | localtime | strftime("%H:%M:%S"))"'
