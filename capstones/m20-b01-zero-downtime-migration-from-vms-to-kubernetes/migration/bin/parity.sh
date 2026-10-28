#!/bin/bash
# parity.sh: environment parity between a VM and a pod. Same variable names? Same values? Values are never printed:
# only the first 12 characters of their SHA-256.
set -euo pipefail
h(){ sha256sum | cut -c1-12; }
vm=$(ssh -q asha@10.0.201.11 sudo cat /etc/allcs-api.env | grep -v '^#')
pod=$(kubectl -n allcs exec deploy/allcs-api -- env | grep -E '^(APP_VERSION|DB_HOST|DB_POOL|DB_PASSWORD|SESSION_SECRET)=')
printf '%-16s %-14s %-14s %s\n' VARIABLE web-01 pod match
for k in $(echo "$vm" | cut -d= -f1 | sort); do
  a=$(echo "$vm" | grep "^$k=" | cut -d= -f2- | h); b=$(echo "$pod" | grep "^$k=" | cut -d= -f2- | h)
  printf '%-16s %-14s %-14s %s\n' $k $a $b "$([ "$a" = "$b" ] && echo yes || echo DIFFERENT)"
done
