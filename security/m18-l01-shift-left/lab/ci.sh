#!/usr/bin/env bash
# ci.sh: small helpers around the lab Gitea REST API (as asha; her token is read inside the lab, never shown)
#   ./ci.sh runs | jobs RUN_ID | log JOB_ID | wait
set -euo pipefail
C=shiftleft-lab; R=/repos/allcsvideos/allcsvideos-platform
api(){ docker exec $C sh -c "curl -s -H \"Authorization: token \$(cat /home/asha/.gitea-token)\" 'http://gitea:3000/api/v1$1'"; }
case ${1:-} in
runs) api "$R/actions/runs?limit=${2:-8}" | jq -c '.workflow_runs[] | [.id,.run_number,.event,.display_title,.status,.conclusion,.head_branch]';;
jobs) api "$R/actions/runs/$2/jobs" | jq -c '.jobs[] | [.id,.name,.status,.conclusion,.started_at,.completed_at]';;
log)  api "$R/actions/jobs/$2/logs";;
wait) sleep 5
      while api "$R/actions/runs?limit=5" | jq -e '[.workflow_runs[] | select(.status=="queued" or .status=="in_progress" or .status=="waiting")] | length > 0' >/dev/null; do sleep 3; done
      api "$R/actions/runs?limit=1" | jq -c '.workflow_runs[0] | [.id,.run_number,.event,.status,.conclusion]';;
*) echo "usage: $0 runs | jobs RUN_ID | log JOB_ID | wait"; exit 1;;
esac
