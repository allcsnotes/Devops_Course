#!/usr/bin/env bash
# down.sh: removes every imm-* container (and with imm-docker, everything built inside it), volumes, network, images.
P=imm
for c in $(docker ps -aq --filter label=lab=$P); do docker rm -f -v "$c" >/dev/null; done
for v in $(docker volume ls -q --filter label=lab=$P); do docker volume rm "$v" >/dev/null; done
docker network rm $P-net >/dev/null 2>&1
docker rmi $P-node:1.0 $P-control:1.0 $P-build:1.0 >/dev/null 2>&1
echo "lab down. Check (should print nothing):"
docker ps -aq --filter label=lab=$P; docker volume ls -q --filter label=lab=$P; docker network ls -q --filter name=$P-net
