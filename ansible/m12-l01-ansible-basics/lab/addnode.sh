#!/usr/bin/env bash
# addnode.sh <host> <last octet>: one more managed node, same recipe (used in M12-L02 for web-03).
#   NET=10.0.122 bash addnode.sh web-03 13
set -euo pipefail
cd "$(dirname "$0")"
NET=${NET:-10.0.12}; P=ans; h=$1; ip=$NET.$2
docker run -d --label lab=$P --privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock \
  --name $P-$h --hostname $h --network $P-net --ip $ip $P-node:1.0 >/dev/null
docker exec $P-control bash -c "grep -q ' $h\$' /etc/hosts || echo '$ip $h' >> /etc/hosts"
KEY=$(docker exec $P-control cat /home/asha/.ssh/id_ed25519.pub); sleep 5
docker cp setup-node.sh $P-$h:/root/ && docker exec $P-$h bash /root/setup-node.sh "$KEY"
echo "node up: $h ($ip)"
