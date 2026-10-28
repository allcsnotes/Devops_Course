# checks.sh: settings and check functions for hc (sourced by bin/hc).
# Every check prints one line: SEVERITY <tab> CHECK <tab> DETAIL
# shellcheck shell=bash disable=SC2153  # settings come from printf -v

KEYS=(DISK_WARN DISK_CRIT INODE_WARN INODE_CRIT MEM_WARN MEM_CRIT
      LOAD_WARN LOAD_CRIT MOUNTS SERVICES ENDPOINTS HTTP_TIMEOUT
      WEBHOOK_URL)

load_conf() {   # KEY=value lines, read as data: the file never runs
  local key value
  [[ -r $1 ]] || die "cannot read config $1"
  while IFS='=' read -r key value; do
    [[ -z $key || $key == '#'* ]] && continue
    [[ " ${KEYS[*]} " == *" $key "* ]] || die "unknown setting $key in $1"
    printf -v "$key" '%s' "$value"
  done < "$1"
  for key in "${KEYS[@]}"; do
    [[ -v $key ]] || die "missing setting $key in $1"
  done
}

result() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }

rate() {   # rate VALUE WARN CRIT, for numbers where higher is worse
  if (( $1 >= $3 )); then echo CRIT
  elif (( $1 >= $2 )); then echo WARN
  else echo OK; fi
}

check_disk() {   # space and inodes: either one can fill up
  local used inodes sev
  if ! used=$(df -P "$1" | awk 'NR == 2 {print int($5)}') ||
     ! inodes=$(df -Pi "$1" | awk 'NR == 2 {print int($5)}'); then
    result CRIT "disk $1" "cannot check"; return
  fi
  sev=$(rate "$used" "$DISK_WARN" "$DISK_CRIT")
  result "$sev" "disk $1" "${used}% used"
  sev=$(rate "$inodes" "$INODE_WARN" "$INODE_CRIT")
  result "$sev" "inodes $1" "${inodes}% used"
}

check_memory() {   # MemAvailable: what programs can still get
  local avail total pct sev=OK
  avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  pct=$(( avail * 100 / total ))
  if (( pct <= MEM_CRIT )); then sev=CRIT
  elif (( pct <= MEM_WARN )); then sev=WARN; fi
  result "$sev" memory "${pct}% available"
}

check_load() {   # 1-minute load per CPU; bash has no decimals, awk does
  local per_cpu sev
  per_cpu=$(awk -v n="$(nproc)" '{printf "%.2f", $1 / n}' /proc/loadavg)
  sev=$(awk -v l="$per_cpu" -v w="$LOAD_WARN" -v c="$LOAD_CRIT" \
    'BEGIN {print (l >= c) ? "CRIT" : (l >= w) ? "WARN" : "OK"}')
  result "$sev" load "$per_cpu per CPU"
}

check_service() {
  local state
  state=$(systemctl is-active "$1" || true)
  if [[ $state == active ]]; then result OK "service $1" active
  else result CRIT "service $1" "$state"; fi
}

run_checks() {   # run_checks LIBDIR
  local m s mounts services endpoints
  read -ra mounts <<< "$MOUNTS"
  read -ra services <<< "$SERVICES"
  read -ra endpoints <<< "$ENDPOINTS"
  for m in "${mounts[@]}"; do check_disk "$m"; done
  check_memory
  check_load
  for s in "${services[@]}"; do check_service "$s"; done
  python3 "$1/http_check.py" "$HTTP_TIMEOUT" "${endpoints[@]}"
}

worst() {   # the worst severity in a list of results
  local sev status=OK
  while IFS=$'\t' read -r sev _; do
    case $sev in
      CRIT) status=CRIT ;;
      WARN) [[ $status == CRIT ]] || status=WARN ;;
    esac
  done <<< "$1"
  echo "$status"
}
