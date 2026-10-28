#!/bin/sh
# naive.sh: what a tired engineer does at 2 a.m.: paste every alert and the last 800 error lines, and ask.
cd /work
{ echo "Production is down. Here are all our alerts and the latest error logs. What's wrong?"
  echo; echo "ALERTS:"
  jq -c '.[] | {alert: .labels.alertname, service: .labels.service, instance: .labels.instance, route: .labels.route, summary: .annotations.summary}' incident/alerts.json
  echo; echo "LOGS:"
  grep -i error incident/logs-all.txt | tail -n 800
} > prompts/naive.txt
echo "prompt: $(jq length incident/alerts.json) alerts, $(grep -c '' prompts/naive.txt) lines, $(wc -c < prompts/naive.txt) characters"
