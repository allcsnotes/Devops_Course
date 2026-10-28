#!/bin/bash
# ci.sh: the checks a pull request must pass before any observability config reaches the stack.
# promtool and amtool run from the same pinned images the stack uses, so this works on a laptop or a CI runner.
set -e
cd "$(dirname "$0")"
promtool() { docker run --rm -v "$PWD":/w -w /w --entrypoint promtool prom/prometheus:v3.15.0 "$@"; }
amtool()   { docker run --rm -v "$PWD":/w -w /w --entrypoint amtool prom/alertmanager:v0.34.1 "$@"; }
promtool check config prometheus/prometheus.yml
(cd prometheus && promtool test rules tests.yml)
amtool check-config alertmanager/alertmanager.yml
amtool config routes test --config.file=alertmanager/alertmanager.yml severity=page team=platform
