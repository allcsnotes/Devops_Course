#!/usr/bin/env bash
# Builds the M04-L03 lab: seven Ubuntu 24.04 machines on three isolated Docker networks.
# The course addresses are set on the interfaces with `ip`, like a static network config:
#   "the internet"      192.0.2.0/24   isp .1, lukas-laptop .50, bot .66, mirror .80   (documentation range)
#   allcsvideos public  203.0.113.0/24 router .1, bastion .10, isp .254                (documentation range)
#   private subnet A    10.0.1.0/24    router .1, bastion .10, web-01 .11
# isp stands in for the internet's routers: it forwards between 192.0.2.0/24 and 203.0.113.0/24 and, like the real
# internet, has NO route to 10.0.1.0/24. router is the allcsvideos NAT box (IP forwarding on, no NAT rules yet).
# net.ipv4.ip_unprivileged_port_start=1024 restores the normal Linux default (container runtimes set it to 0).
# NET_ADMIN lets ufw, iptables and tcpdump work inside each machine.
set -euo pipefail
cd "$(dirname "$0")"
IMG=ports-lab:m04l03
L=(--label course=devops-m04l03)
N=(--cap-add NET_ADMIN --sysctl net.ipv4.ip_unprivileged_port_start=1024 --init)

if docker ps -a --format '{{.Names}}' | grep -qxE 'isp|router|bastion|web01|lukas|bot|mirror'; then
  echo "A container with one of this lab's names already exists. Run the previous lesson's lab/down.sh first." >&2
  exit 1
fi

docker build -t "$IMG" .
# Three isolated layer-2 segments. Their Docker-side subnets don't matter; we replace the addresses below.
docker network create "${L[@]}" -d macvlan --internal --subnet 172.30.31.0/24 lab-inet
docker network create "${L[@]}" -d macvlan --internal --subnet 172.30.32.0/24 lab-pub
docker network create "${L[@]}" -d macvlan --internal --subnet 172.30.33.0/24 lab-app

mk() { local name=$1 host=$2 net=$3; shift 3
       docker run -d "${L[@]}" "${N[@]}" "$@" --name "$name" --hostname "$host" --network "lab-$net" "$IMG" >/dev/null; }
mk isp     isp     inet --sysctl net.ipv4.ip_forward=1; docker network connect lab-pub isp
mk router  router  pub  --sysctl net.ipv4.ip_forward=1; docker network connect lab-app router
mk bastion bastion pub;                                 docker network connect lab-app bastion
mk web01   web-01  app  --cap-add SYS_PTRACE   # SYS_PTRACE: lets root see other users' sockets in `ss -p`
mk lukas   lukas-laptop inet
mk bot     bot     inet
mk mirror  mirror  inet

# addr <machine> <dev> <cidr>: replace Docker's address with the course address
addr() { docker exec "$1" sh -c "ip -4 addr flush dev $2 && ip addr add $3 dev $2"; }
addr isp eth0 192.0.2.1/24;        addr isp eth1 203.0.113.254/24
addr router eth0 203.0.113.1/24;   addr router eth1 10.0.1.1/24
addr bastion eth0 203.0.113.10/24; addr bastion eth1 10.0.1.10/24
addr web01 eth0 10.0.1.11/24
addr lukas eth0 192.0.2.50/24;     addr bot eth0 192.0.2.66/24;   addr mirror eth0 192.0.2.80/24
for m in router bastion; do docker exec "$m" ip route add default via 203.0.113.254; done
docker exec web01 ip route add default via 10.0.1.1
for m in lukas bot mirror; do docker exec "$m" ip route add default via 192.0.2.1; done

# Users and services
docker exec lukas useradd -m -s /bin/bash lukas
docker cp files/allcsvideos.conf web01:/etc/nginx/sites-available/allcsvideos
docker exec web01 sh -c 'rm /etc/nginx/sites-enabled/default && ln -s /etc/nginx/sites-available/allcsvideos /etc/nginx/sites-enabled/ && mkdir -p /var/www/allcsvideos'
docker cp files/index.html web01:/var/www/allcsvideos/index.html
# web-01 is sized like a 1-CPU server: one nginx worker process
docker exec web01 sh -c "sed -i 's/^worker_processes auto;/worker_processes 1;/' /etc/nginx/nginx.conf && nginx && /usr/sbin/sshd"
docker cp ../copilot.py web01:/home/asha/copilot.py
docker exec web01 chown asha:asha /home/asha/copilot.py
docker cp files/mirror.conf mirror:/etc/nginx/sites-available/mirror
docker exec mirror sh -c 'rm /etc/nginx/sites-enabled/default && ln -s /etc/nginx/sites-available/mirror /etc/nginx/sites-enabled/ && mkdir -p /var/www/mirror/ubuntu && echo "Ubuntu package mirror (lab)" > /var/www/mirror/index.html && nginx'

# Asha's SSH key on the bastion, installed on web-01 (as in the SSH lesson; no passphrase in this lab)
docker exec -u asha bastion sh -c 'ssh-keygen -q -t ed25519 -N "" -C asha@allcsvideos.example.com -f ~/.ssh/id_ed25519 && printf "Host web-01\n  HostName 10.0.1.11\n" > ~/.ssh/config'
docker exec web01 install -d -o asha -g asha -m 700 /home/asha/.ssh
docker exec bastion cat /home/asha/.ssh/id_ed25519.pub | docker exec -i web01 sh -c 'cat > /home/asha/.ssh/authorized_keys && chown asha:asha /home/asha/.ssh/authorized_keys && chmod 600 /home/asha/.ssh/authorized_keys'
docker exec -u asha bastion sh -c 'ssh-keyscan -t ed25519 10.0.1.11 2>/dev/null > ~/.ssh/known_hosts'

# THE STAGED BUG: Course Copilot is started with its default host, 127.0.0.1
docker exec -u asha -d web01 sh -c 'cd /home/asha && exec python3 copilot.py'

# Docker adds two NAT rules for its own DNS helper (127.0.0.11) in every machine. Nothing here uses it, so remove
# them: the iptables / nftables output then holds only what you add in this lesson.
for m in isp router bastion web01 lukas bot mirror; do docker exec "$m" nft delete table ip nat; done

echo
echo "Lab is up. Asha's terminals:  docker exec -it -u asha bastion bash   (then: ssh web-01)"
