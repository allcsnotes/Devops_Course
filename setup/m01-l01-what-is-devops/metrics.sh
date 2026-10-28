#!/bin/sh
# Computes the week's DORA numbers from the demo repo made by make-demo.sh.
# For each deploy tag: lead time = deploy time (tag date) - commit time.
# Recovery time = rollback deploy (deploy-4) - failed deploy (deploy-3).
#
# usage: sh metrics.sh [folder]      (default folder: ./allcsvideos-web)
set -e
cd "${1:-allcsvideos-web}"
for t in $(git tag -l 'deploy-*'); do
  ct=$(git log -1 --format=%ct "$t")
  dt=$(git for-each-ref "refs/tags/$t" --format='%(taggerdate:unix)')
  echo "$t lead_min=$(( (dt-ct)/60 )) commit=$(git log -1 --format=%ad --date=format:'%a %H:%M' "$t") deploy=$(git for-each-ref "refs/tags/$t" --format='%(taggerdate:format:%a %H:%M)') $(git for-each-ref "refs/tags/$t" --format='%(subject)')"
done
f=$(git for-each-ref refs/tags/deploy-3 --format='%(taggerdate:unix)')
r=$(git for-each-ref refs/tags/deploy-4 --format='%(taggerdate:unix)')
echo "recovery_min=$(( (r-f)/60 ))"
