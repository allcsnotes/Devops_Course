#!/usr/bin/env bash
# collect.sh: one target, then any number of files

usage() {
  echo "usage: collect.sh TARGET FILE..." >&2
  exit 2
}
(( $# >= 2 )) || usage

target=$1
shift
echo "target: $target"
while (( $# > 0 )); do
  echo "file: $1 ($# left)"
  shift
done
