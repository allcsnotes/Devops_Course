# source logcli.sh: a "logcli" command that runs Grafana's logcli 3.7.9 in a container on the lab's network,
# talking to Loki at http://loki:3100. (Or install logcli 3.7.9 yourself and export LOKI_ADDR=http://localhost:3100.)
logcli() {
  docker run --rm -i --network m16-logs_default -e LOKI_ADDR=http://loki:3100 \
    --entrypoint /usr/bin/logcli grafana/logcli:3.7.9 "$@"
}
# table: print a LogQL metric result as "labels  value" lines
table() { jq -r '.[] | "\([.metric[]] | join(" "))  \(.value[1])"'; }
