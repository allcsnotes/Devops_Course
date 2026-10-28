#!/bin/sh
# dev-secrets.sh: create local development secrets once (random, git-ignored, never overwritten).
# Real environments get their secrets from a secrets manager instead (module 18).
set -eu
mkdir -p secrets
if [ ! -f secrets/db_password.txt ]; then
  head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' > secrets/db_password.txt
  echo "created secrets/db_password.txt (random, local only)"
fi
