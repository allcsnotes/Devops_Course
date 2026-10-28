#!/bin/bash
# archive.sh RUN: after a run, move the incident logs into runs/RUN-*.log (timeline.py RUN reads them from there),
# then restart the pager and status page so the next run starts fresh.
set -euo pipefail
cd "$(dirname "$0")"
r=$1
for f in pager status deploys timeline; do
  if [ -s incident/$f.log ]; then mv incident/$f.log runs/$r-$f.log; fi
done
docker compose restart pager status
