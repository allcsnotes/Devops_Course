#!/bin/bash
# pipeline.sh VERSION [serial|parallel]: the catalog-api delivery pipeline, run locally, every stage timed.
#   test   unit + integration tests (python:3.13.16-slim)     build  image, BuildKit (builder ci-builder)
#   ship   kind load (stand-in for a registry push and pull)  deploy set image + rollout status (namespace shop)
# serial: test, build, ship, deploy.  parallel: test (3 shards) and build at the same time, then ship, deploy.
set -uo pipefail
V=$1; MODE=${2:-serial}; SRC=$(pwd -P); mkdir -p .ci
now(){ date +%s.%N; }; el(){ awk -v a=$1 -v b=$(now) 'BEGIN{printf "%5.1f", b-a}'; }
stage(){ local n=$1 s=$(now); shift; if "$@" > .ci/$n.log 2>&1; then printf '%s  %-6s %s s  ok\n' "$(date +%H:%M:%S)" $n "$(el $s)"
         else printf '%s  %-6s %s s  FAILED (see .ci/%s.log)\n' "$(date +%H:%M:%S)" $n "$(el $s)" $n; return 1; fi; }
ut(){ docker run --rm --label course=devops -v "$SRC":/src:ro -w /src python:3.13.16-slim python -m unittest "$@"; }
test_all(){ ut discover -s tests -t .; }
test_shards(){ ut tests.test_pricing tests.test_api_a & local a=$!; ut tests.test_api_b & local b=$!; ut tests.test_api_c & local c=$!
               wait $a && wait $b && wait $c; }
build(){ docker buildx build --builder ci-builder --progress=plain --load -t catalog-api:$V --build-arg APP_VERSION=$V .; }
ship(){ kind load docker-image catalog-api:$V --name scenarios; }
deploy(){ kubectl -n shop set image deploy/catalog-api api=catalog-api:$V && kubectl -n shop rollout status deploy/catalog-api --timeout=600s; }
T=$(now); echo "pipeline catalog-api $V ($MODE)"
if [ "$MODE" = parallel ]; then
  stage test test_shards & p1=$!; stage build build & p2=$!; wait $p1 && wait $p2 || exit 1
else
  stage test test_all || exit 1; stage build build || exit 1
fi
stage ship ship || exit 1; stage deploy deploy || exit 1
echo "total $(el $T) s"
