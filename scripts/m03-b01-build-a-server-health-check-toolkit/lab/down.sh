#!/usr/bin/env bash
# down.sh: removes everything up.sh created (both containers, the network, the image).
cd "$(dirname "$0")" || exit 1
docker rm -f web-01 hooks
docker network rm hc-lab
docker image rm hc-lab-web01
