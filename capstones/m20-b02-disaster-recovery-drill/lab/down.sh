#!/bin/bash
# down.sh: removes EVERYTHING this lab created: the kind cluster "dr", every container and volume named dr-*, the dr-net
# network, the lab images and the registry tags. The students' CSV files in ~/dr-lab-students are kept.
set -uo pipefail
P=dr
docker ps -a --format '{{.Names}}' | grep -qx $P-ops && docker exec $P-ops kind delete cluster --name $P 2>/dev/null || true
for c in $(docker ps -a --format '{{.Names}} {{.Label "io.x-k8s.kind.cluster"}}' | awk -v p=$P '$2==p {print $1}'); do docker rm -f "$c" >/dev/null; done
for c in $(docker ps -a --format '{{.Names}}' | grep -E "^$P-"); do docker rm -f -v "$c" >/dev/null; done
for v in $(docker volume ls -q | grep -E "^$P-"); do docker volume rm "$v" >/dev/null; done
docker network rm $P-net >/dev/null 2>&1 || true
for i in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "^($P-|localhost:5001/allcs/)"); do docker rmi "$i" >/dev/null; done
echo "lab down. Check: nothing below should be listed"
docker ps -a -q --filter name=$P-; docker volume ls -q --filter name=$P-; docker network ls -q --filter name=$P-net
