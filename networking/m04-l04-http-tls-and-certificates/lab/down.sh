#!/usr/bin/env bash
# Removes everything the M04-L04 lab created: 7 containers, the tlslab network and the tls-lab:m04l04 image.
# Every key and certificate made in the lab lived only inside these containers, so they are gone too.
set -u
docker rm -f web01 store01 api01 laptop lab-ca lab-dns pebble 2>/dev/null
docker network rm tlslab 2>/dev/null
docker image rm tls-lab:m04l04 2>/dev/null
echo "M04-L04 lab removed. (Optional: docker image rm ghcr.io/letsencrypt/pebble:2.10.1 ghcr.io/letsencrypt/pebble-challtestsrv:2.10.1)"
