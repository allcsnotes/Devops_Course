#!/usr/bin/env bash
# tests/run.sh: tests for healthcheck.sh. Fake df and curl are put first on PATH, so every case is
# deterministic and needs no network. Exits 0 only when every test passes.
set -uo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HC=$HERE/../healthcheck.sh
STUBS=$(mktemp -d)
trap 'rm -rf -- "$STUBS"' EXIT

cat > "$STUBS/df" <<'STUB'
#!/usr/bin/env bash
[[ -n ${FAKE_DF_FAIL:-} ]] && exit 1
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf '/dev/fake 1000 %s 0 %s%% %s\n' "${FAKE_DF_PCT:-10}" "${FAKE_DF_PCT:-10}" "${3:-/}"
STUB
cat > "$STUBS/curl" <<'STUB'
#!/usr/bin/env bash
if [[ -n ${FAKE_CURL_EXIT:-} ]]; then printf '000'; exit "$FAKE_CURL_EXIT"; fi
printf '%s' "${FAKE_HTTP_CODE:-200}"
STUB
chmod +x "$STUBS/df" "$STUBS/curl"
export PATH="$STUBS:$PATH"

pass=0 fail=0
# expect NAME WANTED_EXIT WANTED_TEXT -- ENV... -- ARGS...
expect() {
  local name=$1 want=$2 text=$3; shift 3
  local -a envs=() args=()
  [[ ${1:-} == -- ]] && shift
  while (( $# )) && [[ $1 != -- ]]; do envs+=("$1"); shift; done
  [[ ${1:-} == -- ]] && shift
  args=("$@")
  local out rc
  out=$(env "${envs[@]}" bash "$HC" "${args[@]}" 2>&1); rc=$?
  if [[ $rc == "$want" && $out == *"$text"* ]]; then
    pass=$((pass + 1)); printf 'ok   %s\n' "$name"
  else
    fail=$((fail + 1)); printf 'FAIL %s: exit %s (wanted %s), output: %s\n' "$name" "$rc" "$want" "$out"
  fi
}

expect "disk below warning is OK"          0 "OK disk: / is 42% full"          -- FAKE_DF_PCT=42 --
expect "disk at warning is WARNING"        1 "WARNING disk"                    -- FAKE_DF_PCT=80 --
expect "disk at critical is CRITICAL"      2 "CRITICAL disk"                   -- FAKE_DF_PCT=95 --
expect "custom thresholds"                 1 "warning at 50%"                  -- FAKE_DF_PCT=55 -- -w 50 -c 60
expect "df failing is UNKNOWN"             3 "UNKNOWN disk"                    -- FAKE_DF_FAIL=1 --
expect "url 200 is OK"                     0 "OK http: http://x/healthz answered 200" -- FAKE_DF_PCT=1 FAKE_HTTP_CODE=200 -- -u http://x/healthz
expect "url 301 is OK"                     0 "answered 301"                    -- FAKE_DF_PCT=1 FAKE_HTTP_CODE=301 -- -u http://x/
expect "url 503 is CRITICAL"               2 "CRITICAL http: http://x/ answered 503" -- FAKE_DF_PCT=1 FAKE_HTTP_CODE=503 -- -u http://x/
expect "connection refused is CRITICAL"    2 "failed (curl exit 7)"            -- FAKE_DF_PCT=1 FAKE_CURL_EXIT=7 -- -u http://x/
expect "worst state wins"                  2 "WARNING disk"                    -- FAKE_DF_PCT=85 FAKE_HTTP_CODE=500 -- -u http://x/
expect "json output"                       0 '{"check":"disk","status":"OK","message":"/ is 5% full"}' -- FAKE_DF_PCT=5 -- -j
expect "warning must be below critical"    3 "need warning < critical"         -- -- -w 90 -c 80
expect "thresholds must be numbers"        3 "whole numbers"                   -- -- -w ten
expect "unknown option"                    3 "unknown option -x"               -- -- -x
expect "missing option value"              3 "option -u needs a value"         -- -- -u
expect "stray argument"                    3 "unexpected argument: extra"      -- -- extra
expect "help exits 0"                      0 "usage:"                          -- -- -h

printf '%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
