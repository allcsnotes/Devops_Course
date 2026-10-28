#!/usr/bin/env bash
# morning-check.sh: Asha's morning checks on web-01

host=$(hostname)
today=$(date '+%a %d %b')
used=$(df -P / | awk 'NR == 2 {print int($5)}')
errors=$(awk '$9 >= 500' /var/log/nginx/access.log | wc -l)

echo "Morning check on $host, $today"
echo "disk /       ${used}% used"
echo "5xx errors   $errors"
