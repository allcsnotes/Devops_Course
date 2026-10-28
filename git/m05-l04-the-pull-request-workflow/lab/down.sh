#!/usr/bin/env bash
# Removes everything the M05-L04 lab created: the gitea and git-team containers, the gitea-data volume
# (all lab accounts, tokens and repositories), the git-lab network and the git-team:m05l04 image.
docker rm -f git-team gitea 2>/dev/null
docker volume rm gitea-data 2>/dev/null
docker network rm git-lab 2>/dev/null
docker image rm git-team:m05l04 2>/dev/null
echo "M05-L04 lab removed. (Optional: docker image rm gitea/gitea:28.1.0 gitea/tea:0.16.0)"
