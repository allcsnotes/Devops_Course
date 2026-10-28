#!/usr/bin/env bash
# archive-logs.sh: copy the nginx logs into today's archive folder
set -euo pipefail
dest="$HOME/archive/$(date +%F)"
mkdir -p "$dest"
cd "$dest" || exit 1
for f in /var/log/nginx/*.log; do
  cp "$f" .
done

count() {
  local n
  n=$(find . -type f | wc -l)
  echo "$n files archived"
}
count
