#!/bin/bash
# make-release.sh <version> : package one Course Copilot release as ~/releases/copilot-<version>.tar.gz
# (in a real team the CI pipeline from module 8 builds and stores this artifact; here Asha runs it on the control node)
set -euo pipefail
v=$1; mkdir -p ~/releases
tar -czf ~/releases/copilot-$v.tar.gz -C ~/copilot-src/$v app data requirements.txt
sha256sum ~/releases/copilot-$v.tar.gz
