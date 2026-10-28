#!/bin/bash
# users.sh RATE SECONDS: (re)start the traffic generator pod in namespace lab (the users)
cd "$(dirname "$0")"
kubectl -n lab delete pod traffic --ignore-not-found --wait >/dev/null
sed -e "s/RATE_VALUE/$1/" -e "s/DURATION_VALUE/$2/" traffic.yaml | kubectl apply -f -
