#!/usr/bin/env bash
# gap.sh: where set -e does NOT stop the script
set -euo pipefail

backup() {
  cp /etc/hostname /backup/      # /backup doesn't exist
  echo "backup finished"
}

if backup; then
  echo "backup OK"
fi
backup
echo "never printed"
