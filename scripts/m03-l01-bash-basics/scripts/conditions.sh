#!/usr/bin/env bash
# conditions.sh: if, elif and else
used=42

if [[ $used -ge 80 ]]; then
  echo "WARN: disk at $used%"
elif [[ $used -ge 60 ]]; then
  echo "NOTE: disk at $used%, keep an eye on it"
else
  echo "OK: disk at $used%"
fi
