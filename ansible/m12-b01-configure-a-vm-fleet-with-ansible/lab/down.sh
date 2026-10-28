#!/usr/bin/env bash
# down.sh: removes every fleet-* container (incl. web-05 and the traffic generator), the network and the images.
P=fleet
for c in $(docker ps -aq --filter label=lab=$P); do docker rm -f -v "$c" >/dev/null; done
docker network rm $P-net >/dev/null 2>&1
docker rmi $P-node:1.0 $P-control:1.0 >/dev/null 2>&1
echo "lab down. Check (should print nothing):"
docker ps -aq --filter label=lab=$P; docker network ls -q --filter name=$P-net
