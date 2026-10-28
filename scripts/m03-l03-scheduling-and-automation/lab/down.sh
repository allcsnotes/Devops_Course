#!/usr/bin/env bash
# down.sh: remove the M03-L03 lab server and its image.
set -uo pipefail
docker rm -f web-01
docker image rm web01-systemd
