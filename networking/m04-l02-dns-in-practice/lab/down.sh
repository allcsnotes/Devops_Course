#!/usr/bin/env bash
# Removes everything the M04-L02 lab created: 7 containers, the dnslab network and the dnslab:m04l02 image.
set -u
docker rm -f root-ns tld-ns ns1 resolver web01 api01 api02 2>/dev/null
docker network rm dnslab 2>/dev/null
docker image rm dnslab:m04l02 2>/dev/null
echo "M04-L02 lab removed."
