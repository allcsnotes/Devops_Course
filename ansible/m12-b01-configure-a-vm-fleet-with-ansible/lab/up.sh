#!/usr/bin/env bash
# up.sh: the M12-B01 fleet lab. Everything in Docker on your laptop, network fleet-net 10.0.126.0/24:
#   fleet-control  .10  asha@control: Ansible runs here (ansible-core 2.21.5 + ansible-lint in a venv);
#                       it is also the bastion (the only host allowed to SSH into the fleet)
#   fleet-lb-01    .5   fleet-web-01..04  .11-.14   (later fleet-web-05 .15 with addnode.sh)
# Every server: Ubuntu 24.04, systemd + OpenSSH, standing in for a VM, and BARE like a fresh cloud VM:
# stock sshd config, one default user (asha, her key, passwordless sudo). Ansible does the rest.
# The node/control images and setup-control.sh are shared with M12-L01's lab.
# On the control node it also copies: this lesson folder, release/src -> ~/copilot-src, make-release.sh -> ~.
set -euo pipefail
cd "$(dirname "$0")"
LESSON=$(cd .. && pwd); D=$(basename "$LESSON")
A=../../m12-l01-ansible-basics/lab
P=fleet; NET=10.0.126
L=(--label lab=$P)
SYS=(--privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock)   # systemd (and ufw) inside a container
NODES="lb-01:5 web-01:11 web-02:12 web-03:13 web-04:14"

docker build -q -t $P-node:1.0 "${L[@]}" $A/images/node >/dev/null
docker build -q -t $P-control:1.0 "${L[@]}" $A/images/control >/dev/null
docker network create "${L[@]}" --subnet $NET.0/24 $P-net >/dev/null
HOSTS=(); for n in $NODES web-05:15; do HOSTS+=(--add-host "${n%%:*}:$NET.${n##*:}"); done
docker run -d "${L[@]}" --init --name $P-control --hostname control --network $P-net --ip $NET.10 "${HOSTS[@]}" $P-control:1.0 >/dev/null
for n in $NODES; do h=${n%%:*}; docker run -d "${L[@]}" "${SYS[@]}" --name $P-$h --hostname $h --network $P-net --ip $NET.${n##*:} $P-node:1.0 >/dev/null; done
docker cp $A/setup-control.sh $P-control:/root/ && docker exec $P-control bash /root/setup-control.sh install
KEY=$(docker exec $P-control cat /home/asha/.ssh/id_ed25519.pub)
sleep 5
for n in $NODES; do h=${n%%:*}; docker cp setup-node.sh $P-$h:/root/ && docker exec $P-$h bash /root/setup-node.sh "$KEY"; done

docker cp "$LESSON" $P-control:/home/asha/$D
docker exec $P-control bash -c "cp -r /home/asha/$D/release/src /home/asha/copilot-src && cp /home/asha/$D/release/make-release.sh /home/asha/ \
  && chmod +x /home/asha/make-release.sh && chown -R asha:asha /home/asha/$D /home/asha/copilot-src /home/asha/make-release.sh"
echo "lab up: $P-control + servers ($NODES) on $NET.0/24"
echo "shell as asha:  docker exec -it -u asha -w /home/asha fleet-control bash -l"
