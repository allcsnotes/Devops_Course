#!/usr/bin/env bash
# up.sh: the Ansible lab used in Module 12. Four Ubuntu 24.04 "servers" in Docker, on one private network:
#   ans-control  NET.10  asha@control: the Ansible control node (python3-venv + ssh client, no systemd)
#   ans-web-01   NET.11  ans-web-02 NET.12  ans-db-01 NET.21
#                managed nodes: systemd as PID 1 + OpenSSH, hardened (keys only, no root, AllowUsers asha),
#                asha has passwordless sudo (like a cloud image's default user)
# Usage (from this lab folder or anywhere):
#   bash up.sh            # Ansible NOT installed: you install it yourself (M12-L01)
#   bash up.sh install    # also installs ansible-core 2.21.5 + ansible-lint 26.10.1 in ~/.venvs/ansible (later lessons)
# Options via environment:
#   NET=10.0.12           the /24 to use (default 10.0.12; later lessons pass their own so the IPs match their files)
#   NODES="web-01:11 web-02:12 db-01:21"   host:last-octet list
#   COPY=<folder>         copy a lesson folder to /home/asha/<folder name> on the control node
# asha's SSH key has the FAKE demo passphrase demo-passphrase-123 (lab only).
set -euo pipefail
cd "$(dirname "$0")"
NET=${NET:-10.0.12}; P=ans
NODES=${NODES:-"web-01:11 web-02:12 db-01:21"}
L=(--label lab=$P)
SYS=(--privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock)   # systemd inside a container

docker build -q -t $P-node:1.0 "${L[@]}" images/node >/dev/null
docker build -q -t $P-control:1.0 "${L[@]}" images/control >/dev/null
docker network create "${L[@]}" --subnet $NET.0/24 $P-net >/dev/null
HOSTS=(); for n in $NODES; do HOSTS+=(--add-host "${n%%:*}:$NET.${n##*:}"); done
docker run -d "${L[@]}" --init --name $P-control --hostname control --network $P-net --ip $NET.10 "${HOSTS[@]}" $P-control:1.0 >/dev/null
for n in $NODES; do
  h=${n%%:*}
  docker run -d "${L[@]}" "${SYS[@]}" --name $P-$h --hostname $h --network $P-net --ip $NET.${n##*:} $P-node:1.0 >/dev/null
done
docker cp setup-control.sh $P-control:/root/ && docker exec $P-control bash /root/setup-control.sh "${1:-}"
KEY=$(docker exec $P-control cat /home/asha/.ssh/id_ed25519.pub)
sleep 5   # let systemd and sshd start
for n in $NODES; do
  h=${n%%:*}
  docker cp setup-node.sh $P-$h:/root/ && docker exec $P-$h bash /root/setup-node.sh "$KEY"
done
if [ -n "${COPY:-}" ]; then
  d=$(basename "$COPY")
  docker cp "$COPY" $P-control:/home/asha/$d && docker exec $P-control chown -R asha:asha /home/asha/$d
  echo "copied $COPY to /home/asha/$d"
fi
echo "lab up: $P-control + nodes ($NODES) on $NET.0/24"
echo "shell as asha:  docker exec -it -u asha -w /home/asha $P-control bash -l"
