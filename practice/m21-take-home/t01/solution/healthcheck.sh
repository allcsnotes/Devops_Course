#!/usr/bin/env bash
# healthcheck.sh: check one disk and one HTTP endpoint, Nagios style.
# Exit codes: 0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN (bad usage or a check that could not run).
set -euo pipefail

readonly VERSION=1.0.0
DISK_PATH=/
WARN=80
CRIT=90
URL=""
TIMEOUT=5
JSON=0
WORST=0
declare -a RESULTS=()

usage() {
  cat <<USAGE
usage: ${0##*/} [-d PATH] [-w PCT] [-c PCT] [-u URL] [-t SECONDS] [-j] [-h] [-V]
  -d PATH     filesystem to check (default /)
  -w PCT      warning when disk use is at or above PCT (default 80)
  -c PCT      critical when disk use is at or above PCT (default 90)
  -u URL      also check that URL answers 2xx or 3xx
  -t SECONDS  connect and total timeout for the URL check (default 5)
  -j          print one JSON object per check instead of text
USAGE
}

die() { echo "UNKNOWN: $*" >&2; exit 3; }

is_int() { [[ $1 =~ ^[0-9]+$ ]]; }

# record NAME STATE(0-3) MESSAGE
record() {
  local name=$1 state=$2 msg=$3 label
  case $state in 0) label=OK ;; 1) label=WARNING ;; 2) label=CRITICAL ;; *) label=UNKNOWN ;; esac
  if (( state > WORST )); then WORST=$state; fi
  if (( JSON )); then
    msg=${msg//\\/\\\\}; msg=${msg//\"/\\\"}
    RESULTS+=("{\"check\":\"$name\",\"status\":\"$label\",\"message\":\"$msg\"}")
  else
    RESULTS+=("$label $name: $msg")
  fi
}

check_disk() {
  local pct
  if ! pct=$(df -P -- "$DISK_PATH" 2>/dev/null | awk 'NR==2 {sub("%", "", $5); print $5}'); then
    record disk 3 "df failed for $DISK_PATH"; return
  fi
  if ! is_int "${pct:-x}"; then record disk 3 "cannot read usage of $DISK_PATH"; return; fi
  if (( pct >= CRIT )); then record disk 2 "$DISK_PATH is ${pct}% full (critical at ${CRIT}%)"
  elif (( pct >= WARN )); then record disk 1 "$DISK_PATH is ${pct}% full (warning at ${WARN}%)"
  else record disk 0 "$DISK_PATH is ${pct}% full"; fi
}

check_url() {
  local code rc=0
  code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout "$TIMEOUT" -m "$TIMEOUT" -- "$URL") || rc=$?
  if (( rc != 0 )); then record http 2 "$URL failed (curl exit $rc)"; return; fi
  case $code in
    2??|3??) record http 0 "$URL answered $code" ;;
    *) record http 2 "$URL answered $code" ;;
  esac
}

main() {
  local opt
  while getopts ':d:w:c:u:t:jhV' opt; do
    case $opt in
      d) DISK_PATH=$OPTARG ;;
      w) WARN=$OPTARG ;;
      c) CRIT=$OPTARG ;;
      u) URL=$OPTARG ;;
      t) TIMEOUT=$OPTARG ;;
      j) JSON=1 ;;
      h) usage; exit 0 ;;
      V) echo "${0##*/} $VERSION"; exit 0 ;;
      :) usage >&2; die "option -$OPTARG needs a value" ;;
      *) usage >&2; die "unknown option -$OPTARG" ;;
    esac
  done
  shift $((OPTIND - 1))
  (( $# == 0 )) || die "unexpected argument: $1"
  if ! is_int "$WARN" || ! is_int "$CRIT"; then die "thresholds must be whole numbers"; fi
  (( WARN < CRIT && CRIT <= 100 )) || die "need warning < critical <= 100 (got $WARN and $CRIT)"
  if ! is_int "$TIMEOUT" || (( TIMEOUT == 0 )); then die "timeout must be a positive whole number"; fi
  command -v df >/dev/null || die "df not found"

  check_disk
  if [[ -n $URL ]]; then
    command -v curl >/dev/null || die "curl not found"
    check_url
  fi
  printf '%s\n' "${RESULTS[@]}"
  exit "$WORST"
}

main "$@"
