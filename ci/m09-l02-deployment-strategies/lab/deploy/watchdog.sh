#!/bin/bash
# ~/deploy/watchdog.sh : guards a canary. Every second it reads the last 5 s of the load balancer log;
# when more than 5% of green's requests failed (status 500 and up), it sends all traffic back to blue.
source ~/deploy/lib.sh
LOG=/srv/lb/log/lb.log WINDOW=5 MAX=5 MIN=10
while sleep 1; do
  from=$(( $(date +%s) - WINDOW ))
  read -r total bad < <(tail -n 3000 $LOG |
    awk -v from=$from '$1 >= from && $2 == "green" { t++; if ($4 >= 500) b++ } END { print t+0, b+0 }')
  rate=$(( total ? bad * 100 / total : 0 ))
  log "green: $bad of $total requests failed in the last ${WINDOW}s ($rate%)"
  if (( total >= MIN && rate > MAX )); then
    lb_route blue; lb_reload
    log "error rate above $MAX%: ROLLBACK. all traffic back to blue"
    exit 1
  fi
done
