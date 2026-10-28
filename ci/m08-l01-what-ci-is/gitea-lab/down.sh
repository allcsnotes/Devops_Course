#!/usr/bin/env bash
# down.sh - removes everything up.sh created: the runner first (it cleans up its own job containers), any job
# container left behind, Gitea, both volumes and the network. Your local git clone is not touched.
cd "$(dirname "$0")"
docker rm -f gitea-runner 2>/dev/null
for c in $(docker ps -aq --filter name=GITEA-ACTIONS-TASK --filter label=course=devops); do docker rm -f -v "$c"; done
docker rm -f gitea 2>/dev/null
docker volume rm gitea-data gitea-runner-data 2>/dev/null
docker network rm ci-lab 2>/dev/null
echo "lab removed"
