#!/bin/bash
# lab-ci.sh PR_NUMBER (runs as root inside the git-team container): the lab's stand-in for a CI server (Module 8 replaces it
# with GitHub Actions). It fetches the pull request's head commit from Gitea, runs the hc test suite and a config check,
# and reports the result to Gitea as a commit status named ci/hc-tests, as the ci-bot account (REST API:
# POST /repos/{owner}/{repo}/statuses/{sha}). Gitea's branch protection requires that status before a merge.
set -uo pipefail
PR=$1; R=allcsvideos/allcsvideos-ops; API=http://gitea:3000/api/v1; TOK=$(cat /root/.gitea-token)
api(){ curl -s -H "Authorization: token $TOK" -H 'Content-Type: application/json' "$@"; }
sha=$(api $API/repos/$R/pulls/$PR | jq -r .head.sha)
st(){ api -X POST $API/repos/$R/statuses/$sha -d "$(jq -nc --arg s "$1" --arg d "$2" '{state:$s,context:"ci/hc-tests",description:$d}')" >/dev/null; }
st pending "running the hc tests"
# the work runs as the unprivileged user ci (hc refuses to run as root), in a fresh checkout
w=$(runuser -u ci -- mktemp -d)
ciu(){ runuser -u ci -- bash -c "cd $w && $1"; }
ciu "git init -q && git fetch -q http://gitea:3000/$R.git refs/pull/$PR/head && git checkout -q FETCH_HEAD"
echo "ci/hc-tests: pull request #$PR at ${sha:0:7}"
echo "\$ check-config hc/hc.conf"
if out=$(ciu "/opt/check-config.sh hc/hc.conf" 2>&1); then echo "$out"; cfg=0
else echo "$out"; cfg=1; fi
echo "\$ bash hc/tests/run.sh"
tests=$(ciu "bash hc/tests/run.sh" 2>&1); rc=$?; echo "$tests"
sum=$(tail -1 <<< "$tests")
if (( cfg == 0 && rc == 0 )); then st success "$sum"; echo "result: success"
elif (( cfg )); then st failure "$out"; echo "result: failure"
else st failure "$sum"; echo "result: failure"; fi
rm -rf "$w"
