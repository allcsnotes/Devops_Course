#!/usr/bin/env bash
# down.sh: removes everything up.sh created (containers, job containers, volumes, network, image).
cd "$(dirname "$0")"
P=tfci
docker rm -f $P-runner 2>/dev/null
for c in $(docker ps -aq --filter label=lab=$P); do docker rm -f -v "$c"; done
for c in $(docker ps -aq --filter name=GITEA-ACTIONS-TASK --filter network=$P-net); do docker rm -f -v "$c"; done
for v in $(docker volume ls -q --filter label=lab=$P); do docker volume rm "$v"; done
docker network rm $P-net 2>/dev/null
docker rmi $P-team 2>/dev/null
echo "lab down. Check (should print nothing):"
docker ps -aq --filter label=lab=$P; docker volume ls -q --filter label=lab=$P; docker network ls -q --filter name=$P-net
