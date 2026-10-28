#!/bin/bash
# load.sh N RATE: remember the start time, run the load container, print its summary line
date +%s > /tmp/load-start
N=${1:-300} RATE=${2:-10} docker compose run --rm load 2>&1 | tail -1
