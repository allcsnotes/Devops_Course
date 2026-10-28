#!/usr/bin/env bash
# funcs.sh: functions, arguments, output and exit codes

greet() {
  echo "Hello $1, from $(hostname)"
}

disk_used() {             # the answer is printed: capture it with $( )
  local mount=$1
  df -P "$mount" | awk 'NR == 2 {print int($5)}'
}

is_running() {            # prints nothing: the answer is the exit code
  pgrep -x "$1" > /dev/null
}

greet Asha
used=$(disk_used /data)
echo "/data is ${used}% used"
if is_running nginx; then echo "nginx: running"; fi
if ! is_running apache2; then echo "apache2: not running"; fi
