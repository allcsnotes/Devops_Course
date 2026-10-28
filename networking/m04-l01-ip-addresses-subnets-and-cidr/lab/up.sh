#!/usr/bin/env bash
# Builds the M04-L01 lab on your laptop with Docker:
#   lab-pub   203.0.113.0/24  "the internet side" (a documentation range): bastion .10
#   lab-app1  10.0.1.0/24 + 2001:db8:1::/64  private subnet A: router .1, bastion .10, web01 .11, db01 .21, cache01 .41
#   lab-app2  10.0.2.0/24                    private subnet B: router .1, web02 .11
# Docker's own bridge gateway is moved to .254 so our lab router can sit at .1 (like most networks, and like AWS).
# The router has IP forwarding on, and every server's default route points at it.
# cache01 is deliberately given the WRONG prefix (/28 instead of /24) - that is the bug you fix in the lesson.
set -euo pipefail
cd "$(dirname "$0")"

docker build -t lab-net:m04l01 .

L=(--label course=devops-m04l01)
N=(--cap-add NET_ADMIN)            # lets the containers change their own addresses and routes
docker network create "${L[@]}" --subnet 203.0.113.0/24 --gateway 203.0.113.254 lab-pub
docker network create "${L[@]}" --ipv6 --subnet 10.0.1.0/24 --gateway 10.0.1.254 \
  --subnet 2001:db8:1::/64 --gateway 2001:db8:1::fffe lab-app1
docker network create "${L[@]}" --subnet 10.0.2.0/24 --gateway 10.0.2.254 lab-app2

# The router: one leg in each private subnet, IP forwarding on.
docker run -d "${L[@]}" "${N[@]}" --name router --hostname router --sysctl net.ipv4.ip_forward=1 \
  --network lab-app1 --ip 10.0.1.1 --ip6 2001:db8:1::1 lab-net:m04l01
docker network connect --ip 10.0.2.1 lab-app2 router

# The bastion: public side plus private subnet A.
docker run -d "${L[@]}" "${N[@]}" --name bastion --hostname bastion --network lab-pub --ip 203.0.113.10 lab-net:m04l01
docker network connect --ip 10.0.1.10 --ip6 2001:db8:1::10 lab-app1 bastion

# Servers in subnet A, default route via the router at 10.0.1.1.
for spec in web01:web-01:11 db01:db-01:21 cache01:cache-01:41; do
  IFS=: read -r name host last <<<"$spec"
  docker run -d "${L[@]}" "${N[@]}" --name "$name" --hostname "$host" \
    --network lab-app1 --ip "10.0.1.$last" --ip6 "2001:db8:1::$last" lab-net:m04l01
  docker exec "$name" ip route replace default via 10.0.1.1
done

# web-02 in subnet B, default route via the router at 10.0.2.1.
docker run -d "${L[@]}" "${N[@]}" --name web02 --hostname web-02 --network lab-app2 --ip 10.0.2.11 lab-net:m04l01
docker exec web02 ip route replace default via 10.0.2.1

# THE STAGED BUG: cache-01 gets /28 instead of /24 (a two-character typo). Its default route disappears with it.
docker exec cache01 sh -c 'ip addr del 10.0.1.41/24 dev eth0 && ip addr add 10.0.1.41/28 dev eth0'

echo
echo "Lab is up. Open a shell on a machine with, for example:"
echo "  docker exec -it -u asha web01 bash"
