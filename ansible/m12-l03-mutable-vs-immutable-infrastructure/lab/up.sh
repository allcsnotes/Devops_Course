#!/usr/bin/env bash
# up.sh: the M12-L03 lab. Everything in Docker on your laptop, network imm-net 10.0.123.0/24:
#   imm-control  .10  asha@control   Ansible control node (ansible-core 2.21.5 + ansible-lint in a venv)
#   imm-web-01   .11  imm-web-02 .12 long-lived web servers: systemd + OpenSSH (the MUTABLE world)
#   imm-build    .5   asha@build-01  image-build box: hashicorp/packer:1.16.1 + docker CLI + ansible-core 2.21.5
#   imm-docker   .6   the build box's own Docker engine (docker:29.5.3-dind, TLS), like a CI runner's.
#                     Every golden image, test container, Trivy run, the registry and the "prod" instances
#                     live INSIDE it, so your own Docker only sees the imm-* containers, volumes and images.
# The node/control images and setup scripts are shared with M12-L01's lab.
# This lesson folder is copied to /home/asha/<folder> on both the control node and the build box.
set -euo pipefail
cd "$(dirname "$0")"
LESSON=$(cd .. && pwd); D=$(basename "$LESSON")
A=../../m12-l01-ansible-basics/lab
P=imm; NET=10.0.123
L=(--label lab=$P)
SYS=(--privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock)
NODES="web-01:11 web-02:12"

docker build -q -t $P-node:1.0 "${L[@]}" $A/images/node >/dev/null
docker build -q -t $P-control:1.0 "${L[@]}" $A/images/control >/dev/null
docker build -q -t $P-build:1.0 "${L[@]}" images/build >/dev/null
docker network create "${L[@]}" --subnet $NET.0/24 $P-net >/dev/null
HOSTS=(); for n in $NODES; do HOSTS+=(--add-host "${n%%:*}:$NET.${n##*:}"); done
docker run -d "${L[@]}" --init --name $P-control --hostname control --network $P-net --ip $NET.10 "${HOSTS[@]}" $P-control:1.0 >/dev/null
for n in $NODES; do h=${n%%:*}; docker run -d "${L[@]}" "${SYS[@]}" --name $P-$h --hostname $h --network $P-net --ip $NET.${n##*:} $P-node:1.0 >/dev/null; done
docker cp $A/setup-control.sh $P-control:/root/ && docker exec $P-control bash /root/setup-control.sh install
KEY=$(docker exec $P-control cat /home/asha/.ssh/id_ed25519.pub)
sleep 5
for n in $NODES; do h=${n%%:*}; docker cp $A/setup-node.sh $P-$h:/root/ && docker exec $P-$h bash /root/setup-node.sh "$KEY"; done

# the build box and its own Docker engine
for v in dind certs packertmp; do docker volume create "${L[@]}" $P-$v >/dev/null; done
docker run -d "${L[@]}" --privileged --name $P-docker --hostname docker --network $P-net --ip $NET.6 -e DOCKER_TLS_CERTDIR=/certs \
  -v $P-certs:/certs -v $P-dind:/var/lib/docker -v $P-packertmp:/packer-tmp docker:29.5.3-dind >/dev/null
sleep 8
docker run -d "${L[@]}" --name $P-build --hostname build-01 --network $P-net --ip $NET.5 \
  -v $P-certs:/certs:ro -v $P-packertmp:/packer-tmp $P-build:1.0 >/dev/null
docker cp setup-build.sh $P-build:/root/ && docker exec $P-build bash /root/setup-build.sh

for c in control build; do
  docker cp "$LESSON" $P-$c:/home/asha/$D && docker exec $P-$c chown -R asha:asha /home/asha/$D
done
echo "lab up: $P on $NET.0/24"
echo "control node:  docker exec -it -u asha -w /home/asha imm-control bash -l"
echo "build box:     docker exec -it -u asha -w /home/asha imm-build bash -l"
