#!/usr/bin/env bash
# run.sh: a tiny test runner for hc. Run it as a normal user.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
pass=0 fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export STATE_DIRECTORY=$tmp LOGS_DIRECTORY=$tmp

check() {   # check NAME EXPECTED ACTUAL
  if [[ $2 == "$3" ]]; then echo "ok    $1"; pass=$(( pass + 1 ))
  else echo "FAIL  $1: expected '$2', got '$3'"; fail=$(( fail + 1 )); fi
}
saved() { if [[ -e $tmp/state ]]; then echo yes; else echo no; fi; }

source lib/checks.sh
check "rate 79 is OK" OK "$(rate 79 80 90)"
check "rate 80 is WARN" WARN "$(rate 80 80 90)"
check "rate 95 is CRIT" CRIT "$(rate 95 80 90)"
check "worst is CRIT" CRIT "$(worst $'OK\ta\t-\nCRIT\tb\t-\nWARN\tc\t-')"

bin/hc -c tests/unknown.conf 2> /dev/null
check "unknown setting: exit 3" 3 $?
bin/hc -c tests/ok.conf > /dev/null
check "all OK: exit 0" 0 $?
out=$(bin/hc -n -c tests/warn.conf 2>&1)
check "dry run: exit 1" 1 $?
check "dry run: would alert" 1 "$(grep -c 'would alert OK -> WARN' <<< "$out")"
check "dry run: no state saved" no "$(saved)"
bin/hc -c tests/warn.conf > /dev/null 2>&1
check "WARN: exit 1" 1 $?
check "WARN: log line written" 1 "$(grep -c 'status=WARN' "$tmp/hc.log")"
check "alert failed: no state saved" no "$(saved)"

echo "$pass passed, $fail failed"
(( fail == 0 ))
