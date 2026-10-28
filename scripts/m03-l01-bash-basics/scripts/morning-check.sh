#!/usr/bin/env bash
# morning-check.sh: Asha's morning checks on web-01

log="/var/log/nginx/access.log"
limit=80
mounts=(/ /data)
warnings=0
ok=$'\e[32mOK  \e[0m'
warn=$'\e[33mWARN\e[0m'

echo "Morning check on $(hostname), $(date '+%a %d %b')"

for m in "${mounts[@]}"; do
  used=$(df -P "$m" | awk 'NR == 2 {print int($5)}')
  if [[ $used -ge $limit ]]; then
    echo "$warn  disk $m is ${used}% full"
    warnings=$(( warnings + 1 ))
  else
    echo "$ok  disk $m is ${used}% full"
  fi
done

if pgrep -x nginx > /dev/null; then
  echo "$ok  nginx is running"
else
  echo "$warn  nginx is not running"
  warnings=$(( warnings + 1 ))
fi

errors=$(awk '$9 >= 500' "$log" | wc -l)
if [[ $errors -eq 0 ]]; then
  echo "$ok  no 5xx errors"
else
  echo "$warn  $errors 5xx errors in $log"
  warnings=$(( warnings + 1 ))
fi

if (( warnings == 0 )); then
  echo "${ok}  all checks passed"
else
  echo "${warn}  $warnings check(s) need a look"
fi
