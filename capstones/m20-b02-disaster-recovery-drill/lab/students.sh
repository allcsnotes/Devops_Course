#!/bin/bash
# students.sh start|stop: the simulated students (10 requests a second, 1 in 5 enrolls). They are the users, so they
# live OUTSIDE production and survive the disaster. Every confirmed enrollment goes to $DATA/acks.csv.
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd); DATA=${DATA:-$HOME/dr-lab-students}; P=dr
case ${1:-} in
start) docker ps -a --format '{{.Names}}' | grep -qx $P-students || docker run -d --label course=devops --name $P-students \
         --hostname students --network $P-net --ip 10.0.202.9 --memory 160m -v "$DATA":/data $P-api:1.0 python loadgen.py >/dev/null
       echo "students started (files in $DATA)" ;;
stop)  docker rm -f $P-students >/dev/null 2>&1 || true; echo "students stopped" ;;
*)     echo "usage: bash lab/students.sh start|stop"; exit 1 ;;
esac
