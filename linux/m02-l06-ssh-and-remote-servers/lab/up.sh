#!/usr/bin/env bash
# Builds the SSH lab: two Docker networks and five containers.
#
#   ssh-public    203.0.113.0/24  "the internet side": Asha's laptop .50, Priya's laptop .51, the bastion .10
#   ssh-private   10.0.1.0/24     internal, no way out: the bastion .10, web-01 .11, db-01 .21
#
# The servers run systemd as PID 1 (privileged, private cgroup namespace, as in M02-L03) and OpenSSH on port 22.
# The laptops run no sshd: they are only the ssh client side.
# Log in to Asha's laptop with:   docker exec -it laptop su - asha
set -euo pipefail
cd "$(dirname "$0")"

SYS=(--privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock)

docker build -t ssh-lab-sshd:1 image
docker build -t ssh-lab-db:1 image-db

docker network create --subnet 203.0.113.0/24 ssh-public
docker network create --internal --subnet 10.0.1.0/24 ssh-private

docker create "${SYS[@]}" --name bastion --hostname bastion --network ssh-public --ip 203.0.113.10 ssh-lab-sshd:1
docker network connect --ip 10.0.1.10 ssh-private bastion
docker create "${SYS[@]}" --name web-01 --hostname web-01 --network ssh-private --ip 10.0.1.11 ssh-lab-sshd:1
docker create "${SYS[@]}" --name db-01 --hostname db-01 --network ssh-private --ip 10.0.1.21 ssh-lab-db:1
docker create --name laptop --hostname laptop --network ssh-public --ip 203.0.113.50 ssh-lab-sshd:1 sleep infinity
docker create --name priya-laptop --hostname priya-laptop --network ssh-public --ip 203.0.113.51 ssh-lab-sshd:1 sleep infinity
for c in bastion web-01 db-01 laptop priya-laptop; do docker start "$c" >/dev/null; done
sleep 6                                             # give systemd a moment to boot the servers

for c in bastion web-01 db-01; do
  docker cp setup-server.sh "$c":/root/
  docker exec "$c" bash /root/setup-server.sh
done
docker cp setup-db.sh db-01:/root/ && docker exec db-01 bash /root/setup-db.sh
docker cp setup-laptop.sh laptop:/root/ && docker exec laptop bash /root/setup-laptop.sh asha
docker cp setup-laptop.sh priya-laptop:/root/ && docker exec priya-laptop bash /root/setup-laptop.sh priya
docker cp site laptop:/home/asha/site && docker exec laptop chown -R asha:asha /home/asha/site

echo
echo "Lab is up. Open Asha's laptop with:"
echo "  docker exec -it laptop su - asha"
echo "Fake demo passwords: asha demo-password-123, priya demo-priya-pass, database role allcs demo-db-password"
