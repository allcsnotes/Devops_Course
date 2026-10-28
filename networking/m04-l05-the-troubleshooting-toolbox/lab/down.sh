#!/usr/bin/env bash
# Removes everything the M04-L05 lab created: 6 containers, 2 networks and the toolbox-lab:m04l05 image.
set -u
docker rm -f router laptop ns1 proxy01 web01 api01 2>/dev/null
docker network rm lab-out lab-in 2>/dev/null
docker image rm toolbox-lab:m04l05 2>/dev/null
echo "M04-L05 lab removed."
