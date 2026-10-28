#!/bin/sh
# CI step after the staging deploy: load-test at the planned rate per instance (35 requests a second).
# k6 exits non-zero when an SLO threshold fails, and that fails the pipeline.
set -eu
./k6 run --quiet ${BASE_URL:+-e BASE_URL=$BASE_URL} -e RATE=35 -e DURATION=30s tests/load.js
