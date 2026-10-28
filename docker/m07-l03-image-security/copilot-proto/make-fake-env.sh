#!/usr/bin/env bash
# Writes copilot-proto/.env with a FAKE GitHub token, so Trivy's secret scanner has something to find.
# The token is random letters in the shape of a GitHub personal access token. It is NOT a credential.
# It is generated here (not stored in the repo) so code hosts do not flag this course as leaking a token.
set -eu
cd "$(dirname "$0")"
prefix="gh"; prefix="${prefix}p_"                      # built in two parts on purpose
fake="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 36)"
cat > .env <<ENV
# FAKE demo values for this lesson - not real credentials
APP_VERSION=0.9
GITHUB_TOKEN=${prefix}${fake}
ENV
echo "wrote $(pwd)/.env (FAKE token, line 3)"
