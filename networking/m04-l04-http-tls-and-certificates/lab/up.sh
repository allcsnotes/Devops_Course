#!/usr/bin/env bash
# Builds the M04-L04 lab: one Docker network, tlslab 10.0.44.0/24.
#   web01    .10   web-01: nginx reverse proxy (TLS ends here) + certbot, user asha
#   store01  .11   storefront stand-in: python3 -m http.server 3000
#   api01    .21   API stand-in: apps/api.py on port 8080
#   laptop   .50   lukas-laptop: the client (curl, openssl), user lukas
#   lab-ca   .5    Asha's private lab CA (root + intermediate), user asha
#   lab-dns  .53   pebble-challtestsrv 2.10.1 as the lab DNS server (A records for allcsvideos.test)
#   pebble   .100  Pebble 2.10.1, Let's Encrypt's ACME test server (used from step 14)
set -euo pipefail
cd "$(dirname "$0")"
HERE=$(pwd)
IMG=tls-lab:m04l04
NET=tlslab
L=(--label course=devops-m04l04)

if docker ps -a --format '{{.Names}}' | grep -qxE 'web01|store01|api01|laptop|lab-ca|lab-dns|pebble'; then
  echo "A container with one of this lab's names already exists. Run the previous lesson's lab/down.sh first." >&2
  exit 1
fi

docker build -t "$IMG" .
docker network create "${L[@]}" --subnet 10.0.44.0/24 --gateway 10.0.44.254 $NET
for spec in web01:web-01:10 store01:store-01:11 api01:api-01:21 laptop:lukas-laptop:50 lab-ca:lab-ca:5; do
  IFS=: read -r name host last <<<"$spec"
  docker run -d --init "${L[@]}" --cap-add NET_ADMIN --cap-add NET_RAW --name "$name" --hostname "$host" \
    --network $NET --ip "10.0.44.$last" "$IMG" >/dev/null
done

# Lab DNS server (challtestsrv) and the ACME test server (Pebble). Pebble's config file sets a 90-day certificate.
docker run -d "${L[@]}" --name lab-dns --hostname lab-dns --network $NET --ip 10.0.44.53 \
  ghcr.io/letsencrypt/pebble-challtestsrv:2.10.1 \
  -dnsserver :53 -http01 "" -https01 "" -tlsalpn01 "" -doh "" -defaultIPv4 "" -defaultIPv6 "" -management :8055 >/dev/null
docker run -d "${L[@]}" --name pebble --hostname pebble --network $NET --ip 10.0.44.100 --network-alias pebble \
  -e PEBBLE_VA_NOSLEEP=1 -e PEBBLE_WFE_NONCEREJECT=0 -v "$HERE/pebble-config.json:/test/config/lab.json:ro" \
  ghcr.io/letsencrypt/pebble:2.10.1 -config /test/config/lab.json -dnsserver 10.0.44.53:53 >/dev/null
sleep 2

# DNS records, added through challtestsrv's management API
for h in www.allcsvideos.test allcsvideos.test; do
  docker exec web01 curl -s -X POST -d "{\"host\":\"$h.\",\"addresses\":[\"10.0.44.10\"]}" http://10.0.44.53:8055/add-a
done
docker exec web01 curl -s -X POST -d '{"host":"pebble.","addresses":["10.0.44.100"]}' http://10.0.44.53:8055/add-a
for n in web01 store01 api01 laptop lab-ca; do docker exec "$n" sh -c 'printf "nameserver 10.0.44.53\n" > /etc/resolv.conf'; done

# App stand-ins
docker exec store01 mkdir -p /srv
docker cp ../apps/store store01:/srv/store
docker exec -d store01 sh -c 'python3 -u -m http.server 3000 --directory /srv/store >> /var/log/store.log 2>&1'
docker cp ../apps/api.py api01:/srv/api.py
docker exec -d api01 sh -c 'python3 -u /srv/api.py >> /var/log/api.log 2>&1'

# web-01: nginx with the first (plain HTTP) proxy config, 1 worker like a 1-CPU server
docker cp ../nginx/allcsvideos-v1.conf web01:/etc/nginx/sites-available/allcsvideos
docker exec web01 sh -c "rm /etc/nginx/sites-enabled/default && ln -s /etc/nginx/sites-available/allcsvideos /etc/nginx/sites-enabled/ && sed -i 's/^worker_processes auto;/worker_processes 1;/' /etc/nginx/nginx.conf && mkdir -p /var/www/acme && nginx"
# The later nginx configs go to ~/configs on web-01, so each step is one `sudo cp`
docker exec -u asha web01 mkdir -p /home/asha/configs
for f in ../nginx/*.conf; do docker cp "$f" web01:/home/asha/configs/; done
docker cp ../reload-nginx web01:/home/asha/configs/reload-nginx   # the certbot deploy hook (step 17)
docker exec web01 chown -R asha:asha /home/asha/configs
# Pebble's test CA (it signed Pebble's own HTTPS certificate) and the cert-check tool
docker exec web01 mkdir -p /etc/pebble
docker cp pebble.minica.pem web01:/etc/pebble/pebble.minica.pem
docker cp ../cert-check web01:/usr/local/bin/cert-check
docker exec web01 chmod 755 /usr/local/bin/cert-check
# lab-ca: the extension files Asha uses when signing
docker exec -u asha lab-ca mkdir -p /home/asha/pki
docker cp ../pki/int.ext lab-ca:/home/asha/pki/int.ext
docker cp ../pki/www.ext lab-ca:/home/asha/pki/www.ext
docker exec lab-ca chown -R asha:asha /home/asha/pki

echo
echo "TLS lab is up."
echo "  Asha on web-01:   docker exec -it -u asha web01 bash"
echo "  Asha on lab-ca:   docker exec -it -u asha lab-ca bash"
echo "  Lukas's laptop:   docker exec -it -u lukas laptop bash"
