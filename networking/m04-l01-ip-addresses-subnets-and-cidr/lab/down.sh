#!/usr/bin/env bash
# Removes everything lab/up.sh created: 6 containers, 3 networks and the lab-net:m04l01 image.
set -u
docker rm -f router bastion web01 db01 cache01 web02 2>/dev/null
docker network rm lab-pub lab-app1 lab-app2 2>/dev/null
docker image rm lab-net:m04l01 2>/dev/null
echo "M04-L01 lab removed."
