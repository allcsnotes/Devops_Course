#!/usr/bin/env bash
# Puts the lab back to "before the move" for the safe-migration playbook (step 10 of the README):
#   api01 running again, api -> 10.0.53.21 with the one-day TTL (serial 2026102003), the resolver's cache
#   emptied and primed with the old answer, and a background "storefront" on web01 calling the API every 2 seconds.
set -euo pipefail
Z=/etc/bind/zones/db.allcsvideos.test

docker start api01 >/dev/null
docker exec -d api01 sh -c 'python3 -u -m http.server 8080 --directory /srv/api >> /var/log/api.log 2>&1'

docker exec ns1 sed -i -E -e 's/^( +)[0-9]{10}  ; serial/\12026102003  ; serial/' \
                          -e 's/^api .*/api   86400 IN A      10.0.53.21/' $Z
docker exec ns1 rndc reload allcsvideos.test
docker exec resolver rndc flush
sleep 1
docker exec web01 curl -s http://api.allcsvideos.test:8080/health; echo

# The storefront: one API call every 2 seconds, in the background
docker exec -d web01 sh -c 'while true; do curl -s -o /dev/null --connect-timeout 2 http://api.allcsvideos.test:8080/health; sleep 2; done'
echo "Reset done: api -> 10.0.53.21 (TTL 86400), cached on the resolver, storefront calling every 2 s."
