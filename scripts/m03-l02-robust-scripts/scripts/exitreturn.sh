#!/usr/bin/env bash
# exitreturn.sh: return leaves a function, exit ends the script

check() {
  if [[ ! -d $1 ]]; then
    echo "no such folder: $1" >&2
    return 1
  fi
  echo "found $1"
}

die() {
  echo "fatal: $*" >&2
  exit 1
}

check /data
check /backup || echo "check failed, carrying on"
die "giving up"
echo "never printed"
