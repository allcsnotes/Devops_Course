#!/usr/bin/env bash
# traps.sh: work in a temp file that is always cleaned up
set -euo pipefail

tmp=$(mktemp)
cleanup() {
  rm -f "$tmp"
  echo "cleanup: removed $tmp" >&2
}
trap cleanup EXIT
trap 'echo "error on line $LINENO" >&2' ERR

echo "working in $tmp"
df -P "${1:-/}" > "$tmp"
sleep "${2:-0}"
awk 'NR == 2 {print $6, $5}' "$tmp"
