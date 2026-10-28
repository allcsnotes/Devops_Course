#!/usr/bin/env bash
# morning-check.sh: Asha's morning checks on web-01

log="/var/log/nginx/access.log"
limit=80

echo "Morning check on $(hostname), $(date '+%a %d %b')"

used=$(df -P / | awk 'NR == 2 {print int($5)}')
if [[ $used -ge $limit ]]; then
  echo "WARN  disk / is ${used}% full"
else
  echo "OK    disk / is ${used}% full"
fi

if pgrep -x nginx > /dev/null; then
  echo "OK    nginx is running"
else
  echo "WARN  nginx is not running"
fi

errors=$(awk '$9 >= 500' "$log" | wc -l)
if [[ $errors -eq 0 ]]; then
  echo "OK    no 5xx errors"
else
  echo "WARN  $errors 5xx errors in $log"
fi
