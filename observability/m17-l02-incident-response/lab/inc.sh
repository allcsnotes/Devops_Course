#!/bin/bash
# inc.sh WHO MESSAGE: one timestamped line in the incident log (the scribe's job; the timeline is built from it)
cd "$(dirname "$0")"
line="$(date +%H:%M:%S) $1: $2"
echo "{\"epoch\":$(date +%s),\"who\":\"$1\",\"msg\":$(printf '%s' "$2" | jq -Rs .)}" >> incident/timeline.log
echo "$line"
