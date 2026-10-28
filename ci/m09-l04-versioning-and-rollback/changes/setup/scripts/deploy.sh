#!/usr/bin/env bash
# deploy.sh VERSION: run the catalog release recorded in dist/release-VERSION.txt, by digest.
# The migrate job runs first (Flyway only moves forward), then catalog is replaced.
# A rollback is the same command with an older version: the images go back, the database does not.
set -euo pipefail
VERSION=${1:?usage: scripts/deploy.sh 1.2.3}
REL=dist/release-$VERSION.txt
[[ -f $REL ]] || { echo "no release $VERSION: $REL is missing" >&2; exit 2; }
export CATALOG_IMAGE=$(grep '/catalog@' "$REL") MIGRATE_IMAGE=$(grep '/migrate@' "$REL")
echo "== deploy $VERSION  catalog@${CATALOG_IMAGE#*@sha256:}"
since=$(date -u +%Y-%m-%dT%H:%M:%SZ); start=$SECONDS
docker compose up -d --no-build --wait catalog 2>&1 | grep -E 'Recreated|Exited|Healthy|rror' | awk '!seen[$0]++' || true
echo "== migrate (Flyway)"
docker compose logs --no-log-prefix --since "$since" migrate | grep -E '^(Successfully|Schema|WARNING|ERROR|Current version)' || true
echo "== deployed $VERSION in $((SECONDS - start)) s"
