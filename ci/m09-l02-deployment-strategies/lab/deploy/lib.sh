# ~/deploy/lib.sh - small helpers the deploy scripts share (prod-01 runs Docker; the app network is "prod")
POOLS=/srv/lb/pools       # one file per pool: blue, green  (lines: "<name> <ip>")
CONF=/srv/lb/conf.d
ip_of(){ case $1 in blue-*) echo 10.0.93.1${1#blue-} ;; green-*) echo 10.0.93.2${1#green-} ;; esac; }
log(){ echo "$(date +%T.%3N)  $*"; }

start_app(){   # start_app <name> <version> : one instance of Course Copilot at its fixed address
  docker run -d --name "$1" --network prod --ip "$(ip_of "$1")" --stop-timeout 10 \
    --label course=devops "copilot:$2" >/dev/null
}
stop_app(){    # stop_app <name> : SIGTERM, up to 10 s to finish in-flight requests, then remove
  docker stop -t 10 "$1" >/dev/null && docker rm "$1" >/dev/null
}
wait_ready(){  # wait_ready <name> : readiness = /health answers 200 (checked every 0.2 s, at most 30 s)
  for _ in $(seq 150); do
    curl -sf -o /dev/null --max-time 1 "http://$(ip_of "$1"):8000/health" && return 0
    sleep 0.2
  done
  return 1
}

lb_render(){   # write upstreams.conf from the pool files; a "down" flag drains that server
  for pool in blue green; do
    [[ -s $POOLS/$pool ]] || continue
    echo "upstream $pool {"; echo "    zone $pool 64k;                # shared by all nginx workers"
    while read -r name ip flag; do
      echo "    server $ip:8000 max_fails=1 fail_timeout=5s${flag:+ $flag};   # $name"
    done < "$POOLS/$pool"
    echo "}"
  done > $CONF/upstreams.conf
}
lb_route(){    # lb_route blue | green | <live> <canary> <percent> : write route.conf
  if [[ $# -eq 1 ]]; then
    printf 'map $host $pool {\n    default %s;\n}\n' "$1" > $CONF/route.conf
  else
    printf 'split_clients "${request_id}" $pool {\n    %s%% %s;\n    * %s;\n}\n' "$3" "$2" "$1" > $CONF/route.conf
  fi
}
lb_reload(){   # check the config, then a graceful reload: old workers finish their requests
  docker exec lb nginx -t -q && docker exec lb nginx -s reload
}
pool_add(){ echo "$2 $(ip_of "$2")" >> "$POOLS/$1"; }                       # pool_add <pool> <name>
pool_set(){ sed -i "s/^\($2 [0-9.]*\).*/\1${3:+ $3}/" "$POOLS/$1"; }       # pool_set <pool> <name> [down]
pool_clear(){ : > "$POOLS/$1"; }
