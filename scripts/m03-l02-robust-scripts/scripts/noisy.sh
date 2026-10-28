#!/usr/bin/env bash
# noisy.sh: a log line ends up in the captured value
disk_used() {
  echo "checking $1"
  df -P "$1" | awk 'NR == 2 {print int($5)}'
}
used=$(disk_used /data)
echo "used is: $used"
if (( used > 80 )); then echo "almost full"; fi
