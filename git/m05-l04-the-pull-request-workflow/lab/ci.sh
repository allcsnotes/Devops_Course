#!/usr/bin/env bash
# ci.sh PR_NUMBER: runs the lab CI (lab-ci.sh) for one pull request. It runs the config check and the hc tests on the
# pull request's head commit and posts the result to Gitea as the required status "ci/hc-tests" (as ci-bot).
# Module 8 replaces this with real CI that runs on every push by itself.
set -euo pipefail
docker exec git-team bash /opt/lab-ci.sh "${1:?usage: bash lab/ci.sh PR_NUMBER}"
