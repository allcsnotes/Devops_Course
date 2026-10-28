#!/bin/bash
# down.sh: removes everything this lab created: the kind cluster "mig", every container/volume named mig-*,
# the mig-net network and the lab images. Your working copy (~/migration-lab) is kept; delete it yourself if you like.
set -uo pipefail
P=mig
if docker ps -a --format '{{.Names}}' | grep -qx $P-ops; then
  docker exec $P-ops sh -c "kind get clusters 2>/dev/null | grep -qx $P && kind delete cluster --name $P" || true
fi
for c in $(docker ps -a --format '{{.Names}} {{.Label "io.x-k8s.kind.cluster"}}' | awk -v p=$P '$2==p {print $1}'); do docker rm -f "$c" >/dev/null; done
for c in $(docker ps -a --format '{{.Names}}' | grep -E "^$P-"); do docker rm -f -v "$c" >/dev/null; done
for v in $(docker volume ls -q | grep -E "^$P-"); do docker volume rm "$v" >/dev/null; done
docker network rm $P-net >/dev/null 2>&1 || true
for i in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "^($P-|allcs-api:)"); do docker rmi "$i" >/dev/null; done
echo "lab down. Check: nothing below should be listed"
docker ps -a --filter name=$P- -q; docker volume ls -q --filter name=$P-; docker network ls -q --filter name=$P-net
