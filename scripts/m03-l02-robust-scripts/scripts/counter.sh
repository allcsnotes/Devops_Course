#!/usr/bin/env bash
# counter.sh: count the mounts that are more than 10% full
set -euo pipefail
full=0
for m in / /data; do
  used=$(df -P "$m" | awk 'NR == 2 {print int($5)}')
  echo "checking $m: ${used}%"
  if (( used > 10 )); then (( full++ )); fi
done
echo "$full mount(s) over 10%"
