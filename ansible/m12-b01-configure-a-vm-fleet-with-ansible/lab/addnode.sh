#!/usr/bin/env bash
# addnode.sh <host> <last octet>: one more BARE server, same recipe.   bash addnode.sh web-05 15
set -euo pipefail
cd "$(dirname "$0")"
P=fleet; NET=10.0.126; h=$1
docker run -d --label lab=$P --privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock \
  --name $P-$h --hostname $h --network $P-net --ip $NET.$2 $P-node:1.0 >/dev/null
KEY=$(docker exec $P-control cat /home/asha/.ssh/id_ed25519.pub); sleep 5
docker cp setup-node.sh $P-$h:/root/ && docker exec $P-$h bash /root/setup-node.sh "$KEY"
echo "node up: $h ($NET.$2)"
