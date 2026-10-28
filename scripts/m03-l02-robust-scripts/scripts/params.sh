#!/usr/bin/env bash
# params.sh: what a script receives
echo "script: $0"
echo "count:  $#"
echo "first:  $1"
echo "second: $2"
echo 'quoted "$@":'
for a in "$@"; do echo "  [$a]"; done
echo 'quoted "$*":'
for a in "$*"; do echo "  [$a]"; done
echo 'unquoted $@:'
for a in $@; do echo "  [$a]"; done
