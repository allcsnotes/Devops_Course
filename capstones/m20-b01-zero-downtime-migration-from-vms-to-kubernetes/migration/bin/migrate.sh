#!/bin/bash
# migrate.sh: move the students from the VMs to Kubernetes in steps: 5, 25, 50, 100 %.
# Each step soaks for SOAK seconds (60), then the SLO gate decides. A failed gate sends everyone back to the VMs at once.
set -uo pipefail
SOAK=${SOAK:-60}
for p in ${STEPS:-5 25 50 100}; do
  shift.sh $p
  sleep $SOAK
  if ! gate.sh $SOAK; then
    echo "$(date +%T) gate failed at $p %: rolling back"; shift.sh 0; exit 1
  fi
done
if [ "$p" = 100 ]; then echo "$(date +%T) migration complete: 100 % of students on Kubernetes"
else echo "$(date +%T) every step passed: $p % on Kubernetes"; fi
