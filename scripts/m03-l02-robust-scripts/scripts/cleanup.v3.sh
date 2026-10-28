#!/usr/bin/env bash
# cleanup.sh: delete the files of old releases (staged demo, sandbox only)
set -euo pipefail

dir="$HOME/sandbox/releases/old"
dry_run=0
if [[ ${1:-} == "-n" ]]; then dry_run=1; fi

run() {
  if (( dry_run )); then echo "dry run: $*"; else "$@"; fi
}

cd "$dir"
run rm -f -- ./*.tar.gz
echo "cleanup done"
