#!/bin/bash
# shift.sh PCT: send PCT % of student requests to Kubernetes and the rest to the VMs.
# Writes the edge's split, checks the whole nginx config, then reloads it gracefully (open connections finish).
# A config that fails the check is never loaded: the previous split is put back.
set -euo pipefail
P=$1; F=~/migration/edge/split/weights.conf
cp $F $F.prev
{ echo "# written by shift.sh: $P % of requests go to Kubernetes"
  echo 'split_clients "${request_id}" $pool {'
  if   [ "$P" -ge 100 ]; then echo '    *     k8s_pool;'
  elif [ "$P" -le 0 ];   then echo '    *     vm_pool;'
  else echo "    $P%   k8s_pool;"; echo '    *     vm_pool;'; fi
  echo '}'; } > $F
if ! edge nginx -t -q; then cp $F.prev $F; echo "config check failed: split not changed"; exit 1; fi
edge nginx -s reload 2>/dev/null
echo "$(date +%s%3N) $P" >> ~/migration/k6/out/events.log
echo "$(date +%T) edge: $P % to Kubernetes, $((100-P)) % to the VMs"
