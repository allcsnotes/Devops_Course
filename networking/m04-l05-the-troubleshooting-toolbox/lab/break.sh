#!/usr/bin/env bash
# break.sh <fault> - stages one of the lesson's failures, as root, the way they were set up off camera.
# You then find it with the method and fix it with the commands in the README.
#   1      www.allcsvideos.test points at the retired proxy address 10.0.56.11 (serial 2026102002)
#   2      router drops TCP to 10.0.56.10 port 443
#   2b     nginx on proxy-01 is stopped
#   3      an expired certificate is deployed on proxy-01
#   3b     the staging certificate (staging.allcsvideos.test only) is deployed on proxy-01
#   4      the API process on api-01 is killed
#   4b     the API takes 8 seconds per request
#   5      the API takes 1.5 seconds per request
#   5b     the router adds 100 ms of delay on its outside interface (netem)
#   icmp   the router drops ping requests to the inside network
#   api-up starts the API again after fault 4 (the fix for 4)
set -euo pipefail
Z=/etc/bind/zones/db.allcsvideos.test
case "${1:-}" in
  1)    docker exec ns1 sed -i -e 's/^www     IN A    10.0.56.10/www     IN A    10.0.56.11/' \
                               -e 's/2026102001 ; serial/2026102002 ; serial/' $Z
        docker exec ns1 rndc reload allcsvideos.test ;;
  2)    docker exec router iptables -I FORWARD -p tcp -d 10.0.56.10 --dport 443 -j DROP ;;
  2b)   docker exec proxy01 nginx -s stop ;;
  3)    docker exec proxy01 sh -c 'cp /root/ca/expired.crt /etc/nginx/tls/allcsvideos.crt && nginx -s reload' ;;
  3b)   docker exec proxy01 sh -c 'cp /root/ca/staging.crt /etc/nginx/tls/allcsvideos.crt && cp /root/ca/staging.key /etc/nginx/tls/allcsvideos.key && nginx -s reload' ;;
  4)    docker exec api01 pkill -f /srv/api.py ;;
  api-up) docker exec -d api01 sh -c 'python3 -u /srv/api.py >> /var/log/api.log 2>&1' ;;
  4b)   docker exec api01 sh -c 'echo 8 > /etc/api-delay' ;;
  5)    docker exec api01 sh -c 'echo 1.5 > /etc/api-delay' ;;
  5b)   docker exec router tc qdisc add dev eth0 root netem delay 100ms ;;
  icmp) docker exec router iptables -I FORWARD -p icmp --icmp-type echo-request -d 10.0.56.0/24 -j DROP ;;
  *)    sed -n '2,15p' "$0"; exit 1 ;;
esac
echo "staged: $1"
