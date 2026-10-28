#!/usr/bin/env bash
# Builds the M04-L02 DNS lab: one Docker network, seven Ubuntu 24.04 containers, BIND 9 from Ubuntu's packages.
#   dnslab    10.0.53.0/24 (numbered after the DNS port, 53)
#   root-ns   .2   lab root server, authoritative for "."
#   tld-ns    .3   lab TLD server, authoritative for "test."
#   ns1       .10  authoritative for allcsvideos.test (+ reverse zone 53.0.10.in-addr.arpa), recursion off
#   resolver  .53  recursive caching resolver; its root hints point at the lab root
#   web01     .11  the storefront = the DNS client (stub resolver)
#   api01     .21  old API server, api02 .22 new API server (python3 http.server on port 8080, GET /health)
set -euo pipefail
cd "$(dirname "$0")"
C=config
L=(--label course=devops-m04l02)
IMG=dnslab:m04l02

if docker ps -a --format '{{.Names}}' | grep -qxE 'root-ns|tld-ns|ns1|resolver|web01|api01|api02'; then
  echo "A container with one of this lab's names already exists. Run lab/down.sh (here or in the previous lesson) first." >&2
  exit 1
fi

docker build -t "$IMG" .
docker network create "${L[@]}" --subnet 10.0.53.0/24 --gateway 10.0.53.254 dnslab

for spec in root-ns:root-ns:2 tld-ns:tld-ns:3 ns1:ns1:10 resolver:resolver:53 web01:web-01:11 api01:api-01:21 api02:api-02:22; do
  IFS=: read -r name host last <<<"$spec"
  docker run -d --init "${L[@]}" --name "$name" --hostname "$host" --network dnslab --ip "10.0.53.$last" "$IMG"
done

# Config files for the four DNS servers
for n in root-ns tld-ns ns1 resolver; do docker exec "$n" install -d -o root -g bind /etc/bind/zones; done
docker cp $C/root/named.conf   root-ns:/etc/bind/named.conf
docker cp $C/root/db.root      root-ns:/etc/bind/zones/db.root
docker cp $C/tld/named.conf    tld-ns:/etc/bind/named.conf
docker cp $C/tld/db.test       tld-ns:/etc/bind/zones/db.test
docker cp $C/ns1/named.conf.options    ns1:/etc/bind/named.conf.options
docker cp $C/ns1/named.conf.local      ns1:/etc/bind/named.conf.local
docker cp $C/ns1/db.allcsvideos.test   ns1:/etc/bind/zones/db.allcsvideos.test
docker cp $C/ns1/db.10.0.53            ns1:/etc/bind/zones/db.10.0.53
docker cp $C/resolver/named.conf.options resolver:/etc/bind/named.conf.options
# Keep Ubuntu's real root hints as root.hints.orig, then swap in the lab version
docker exec resolver cp /usr/share/dns/root.hints /usr/share/dns/root.hints.orig
docker cp $C/resolver/root.hints resolver:/usr/share/dns/root.hints
# ns1 and the resolver log to /var/log/named/named.log
for n in ns1 resolver; do
  docker cp $C/named.conf.logging "$n":/etc/bind/named.conf.logging
  docker exec "$n" sh -c 'echo "include \"/etc/bind/named.conf.logging\";" >> /etc/bind/named.conf'
done
# Check the config and start BIND (named) on each DNS server
for n in root-ns tld-ns ns1 resolver; do
  docker exec "$n" sh -c 'chown -R root:bind /etc/bind/zones && chmod 644 /etc/bind/zones/* && named-checkconf && named -u bind'
done

# web-01 asks the lab resolver (what DHCP or netplan would set on a real server)
docker exec web01 sh -c 'printf "nameserver 10.0.53.53\nsearch allcsvideos.test\n" > /etc/resolv.conf'

# The two API stand-ins: GET /health returns which server answered
for i in 01 02; do
  docker exec -i api$i sh -c 'mkdir -p /srv/api && cat > /srv/api/health' < $C/api/health-$i
  docker exec -d api$i sh -c 'python3 -u -m http.server 8080 --directory /srv/api >> /var/log/api.log 2>&1'
done

echo
echo "DNS lab is up. Open a shell with:  docker exec -it -u asha web01 bash   (or ns1, resolver, api01)"
