#!/usr/bin/env bash
# Removes everything the M04-L03 lab created: 7 containers, 3 networks, the ports-lab:m04l03 image,
# and the "web-publish" nginx container from step 15 if it is still running.
set -u
docker rm -f isp router bastion web01 lukas bot mirror web-publish 2>/dev/null
docker network rm lab-inet lab-pub lab-app 2>/dev/null
docker image rm ports-lab:m04l03 2>/dev/null
echo "M04-L03 lab removed."
