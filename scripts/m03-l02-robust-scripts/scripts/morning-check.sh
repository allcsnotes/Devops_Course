#!/usr/bin/env bash
# morning-check.sh v2: Asha's morning checks on web-01, ready for cron
set -euo pipefail

usage() {
  cat <<'HELP'
usage: morning-check.sh [-h] [-v] [-t PERCENT] [-l LOGFILE] [MOUNT...]
  -h          show this help
  -v          verbose: log each step to stderr
  -t PERCENT  warn when a disk is this full (default 80)
  -l LOGFILE  access log to scan (default /var/log/nginx/access.log)
  MOUNT...    disks to check (default / and /data)
exit codes: 0 all OK, 1 something needs a look, 2 usage error
HELP
}

log()  { printf '%s %s\n' "$(date '+%F %T')" "$*" >&2; }
vlog() { if (( verbose )); then log "$@"; fi; }
die()  { log "error: $1"; exit "${2:-1}"; }

limit=80
log_file=/var/log/nginx/access.log
verbose=0
warnings=0

while getopts ':hvt:l:' opt; do
  case $opt in
    h)  usage; exit 0 ;;
    v)  verbose=1 ;;
    t)  limit=$OPTARG ;;
    l)  log_file=$OPTARG ;;
    :)  die "-$OPTARG needs a value (try -h)" 2 ;;
    \?) die "unknown option -$OPTARG (try -h)" 2 ;;
  esac
done
shift $(( OPTIND - 1 ))

if [[ ! $limit =~ ^[0-9]+$ ]] || (( limit < 1 || limit > 100 )); then
  die "-t needs a number from 1 to 100, got '$limit'" 2
fi
if (( $# == 0 )); then set -- / /data; fi

if [[ -t 1 ]]; then
  ok=$'\e[32mOK  \e[0m'; warn=$'\e[33mWARN\e[0m'
else
  ok='OK  '; warn='WARN'
fi

check_disk() {
  local mount=$1 used
  if ! used=$(df -P "$mount" | awk 'NR == 2 {print int($5)}'); then
    echo "$warn  disk $mount: cannot check"; return 1
  fi
  vlog "disk $mount is ${used}% used, limit ${limit}%"
  if (( used >= limit )); then
    echo "$warn  disk $mount is ${used}% full"; return 1
  fi
  echo "$ok  disk $mount is ${used}% full"
}

check_nginx() {
  vlog "looking for an nginx process"
  if ! pgrep -x nginx > /dev/null; then
    echo "$warn  nginx is not running"; return 1
  fi
  echo "$ok  nginx is running"
}

check_errors() {
  local errors
  vlog "scanning $log_file"
  if ! errors=$(awk '$9 >= 500' "$log_file" | wc -l); then
    echo "$warn  cannot read $log_file"; return 1
  fi
  if (( errors > 0 )); then
    echo "$warn  $errors 5xx errors in $log_file"; return 1
  fi
  echo "$ok  no 5xx errors"
}

echo "Morning check on $(hostname), $(date '+%a %d %b')"
for m in "$@"; do
  check_disk "$m" || warnings=$(( warnings + 1 ))
done
check_nginx || warnings=$(( warnings + 1 ))
check_errors || warnings=$(( warnings + 1 ))

if (( warnings > 0 )); then
  log "finished: $warnings check(s) need a look"
  exit 1
fi
log "finished: all checks passed"
