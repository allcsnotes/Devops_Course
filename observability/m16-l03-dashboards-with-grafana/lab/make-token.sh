#!/bin/sh
# make-token.sh: creates the "deploy-bot" service account (role Editor) in the lab Grafana and writes one of its
# tokens to .env as GRAFANA_TOKEN (.env is in .gitignore, like a CI secret). The token is never printed.
# Uses the FAKE lab admin password from compose.yaml.
set -eu
G=localhost:3000; A=admin:fake-admin-pass-123
ID=$(curl -s -u $A -H 'Content-Type: application/json' -X POST $G/api/serviceaccounts \
      -d '{"name": "deploy-bot", "role": "Editor"}' | jq -r .id)
KEY=$(curl -s -u $A -H 'Content-Type: application/json' -X POST $G/api/serviceaccounts/$ID/tokens \
      -d '{"name": "deploy"}' | jq -r .key)
umask 077; printf 'GRAFANA_TOKEN=%s\n' "$KEY" > .env
echo "service account deploy-bot (id $ID): token written to .env"
