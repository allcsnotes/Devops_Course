#!/usr/bin/env bash
# down.sh: remove the M03-L04 lab (three containers and the network).
set -uo pipefail
docker rm -f web-01 api-01 copilot-01
docker network rm lab-net
