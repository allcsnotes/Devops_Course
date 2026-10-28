#!/usr/bin/env bash
# Builds the M04-L05 troubleshooting lab: six Ubuntu 24.04 machines on two isolated networks.
#   outside  10.0.55.0/24  router .1, laptop .50 (Asha, on the same side of the internet as Lukas), ns1 .53 (BIND)
#   inside   10.0.56.0/24  router .1, proxy-01 .10 (nginx, TLS), web-01 .20 (storefront), api-01 .30 (API)
# router forwards between the two (no NAT, so every address stays visible) and can filter with iptables.
# The networks are macvlan + --internal: no Docker gateway, routes are set by hand like a static network config.
# NET_ADMIN: iptables / tc / ip route inside the machines.
set -euo pipefail
cd "$(dirname "$0")"
IMG=toolbox-lab:m04l05
L=(--label course=devops-m04l05)
N=(--cap-add NET_ADMIN --init)

if docker ps -a --format '{{.Names}}' | grep -qxE 'router|laptop|ns1|proxy01|web01|api01'; then
  echo "A container with one of this lab's names already exists. Run the previous lesson's lab/down.sh first." >&2
  exit 1
fi

docker build -t "$IMG" .
docker network create "${L[@]}" -d macvlan --internal --subnet 10.0.55.0/24 --gateway 10.0.55.254 lab-out
docker network create "${L[@]}" -d macvlan --internal --subnet 10.0.56.0/24 --gateway 10.0.56.254 lab-in

mk() { local name=$1 host=$2 net=$3 ip=$4; shift 4
       docker run -d "${L[@]}" "${N[@]}" "$@" --name "$name" --hostname "$host" --network "lab-$net" --ip "$ip" "$IMG" >/dev/null; }
mk router  router   out 10.0.55.1 --sysctl net.ipv4.ip_forward=1
docker network connect --ip 10.0.56.1 lab-in router
mk laptop  laptop   out 10.0.55.50
mk ns1     ns1      out 10.0.55.53
mk proxy01 proxy-01 in  10.0.56.10
mk web01   web-01   in  10.0.56.20
mk api01   api-01   in  10.0.56.30
docker exec laptop ip route add 10.0.56.0/24 via 10.0.55.1
docker exec ns1    ip route add 10.0.56.0/24 via 10.0.55.1
for m in proxy01 web01 api01; do docker exec "$m" ip route add default via 10.0.56.1; done

# The laptop asks the lab DNS server (what DHCP would set), and gets the curl format file
docker exec laptop sh -c 'printf "nameserver 10.0.55.53\n" > /etc/resolv.conf'
docker cp ../curl-format.txt laptop:/home/asha/curl-format.txt
docker exec laptop chown asha:asha /home/asha/curl-format.txt

# ns1: BIND, authoritative for allcsvideos.test
docker exec ns1 install -d -o root -g bind /etc/bind/zones
docker cp ns1/named.conf.options ns1:/etc/bind/named.conf.options
docker cp ns1/named.conf.local   ns1:/etc/bind/named.conf.local
docker cp ns1/db.allcsvideos.test ns1:/etc/bind/zones/db.allcsvideos.test
docker exec ns1 sh -c 'chown root:bind /etc/bind/zones/* && chmod 644 /etc/bind/zones/* && named-checkconf && named -u bind'

# web-01 and api-01 stand-ins (python3). /etc/api-delay = seconds the API sleeps per request (0 = normal).
docker exec web01 mkdir -p /srv/web
docker cp web/index.html web01:/srv/web/index.html
docker exec -d web01 sh -c 'python3 -u -m http.server 8080 --directory /srv/web >> /var/log/web.log 2>&1'
docker cp api/api.py api01:/srv/api.py
docker exec api01 sh -c 'echo 0 > /etc/api-delay && chown asha /etc/api-delay'
docker exec -d api01 sh -c 'python3 -u /srv/api.py >> /var/log/api.log 2>&1'

# proxy-01: a lab CA and certificates (good, expired, staging), then nginx as the TLS reverse proxy
docker cp proxy/mkcerts.sh proxy01:/root/mkcerts.sh
docker exec proxy01 /root/mkcerts.sh
docker exec proxy01 sh -c 'install -d /etc/nginx/tls && cp /root/ca/good.crt /etc/nginx/tls/allcsvideos.crt && cp /root/ca/site.key /etc/nginx/tls/allcsvideos.key && chmod 600 /etc/nginx/tls/allcsvideos.key'
docker cp proxy/allcsvideos.conf proxy01:/etc/nginx/sites-available/allcsvideos
docker exec proxy01 sh -c 'rm /etc/nginx/sites-enabled/default && ln -s /etc/nginx/sites-available/allcsvideos /etc/nginx/sites-enabled/ && sed -i "s/^worker_processes auto;/worker_processes 1;/" /etc/nginx/nginx.conf && nginx -t && nginx'

# The laptop (and proxy-01) trust the lab CA, like a company CA. The CA key never leaves proxy-01.
docker exec proxy01 cat /root/ca/ca.crt | docker exec -i laptop sh -c 'cat > /usr/local/share/ca-certificates/allcsvideos-lab-ca.crt && update-ca-certificates >/dev/null'
docker exec proxy01 sh -c 'cp /root/ca/ca.crt /usr/local/share/ca-certificates/allcsvideos-lab-ca.crt && update-ca-certificates >/dev/null 2>&1'

echo
echo "Lab is up. Open a machine with:  docker exec -it -u asha laptop bash   (or router, ns1, proxy01, api01)"
