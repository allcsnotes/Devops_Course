#!/usr/bin/env bash
# masked.sh: local can hide a failure
set -euo pipefail

masked() {
  local value=$(grep '^limit=' /etc/morning-check.conf)
  echo "masked: value is '$value'"
}
honest() {
  local value
  value=$(grep '^limit=' /etc/morning-check.conf)
  echo "honest: value is '$value'"
}
masked
honest
echo "never printed"
