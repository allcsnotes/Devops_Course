#!/bin/bash
# flag.sh NAME on|off: flip a feature flag (a kill switch, module 9, lesson 3). The API reads flags/flags.json on
# every request, so no deploy is needed. A file stands in for a flag service like flagd.
set -euo pipefail
cd "$(dirname "$0")"
[[ $2 == on ]] && val=true || val=false
tmp=$(mktemp flags/.f.XXXX); jq --arg n "$1" --argjson v $val '.[$n] = $v' flags/flags.json > "$tmp" && mv "$tmp" flags/flags.json
chmod 644 flags/flags.json
echo "{\"epoch\":$(date +%s),\"flag\":\"$1\",\"value\":\"$2\"}" >> incident/flags.log
echo "$(date +%H:%M:%S) flag $1 = $2: $(cat flags/flags.json)"
