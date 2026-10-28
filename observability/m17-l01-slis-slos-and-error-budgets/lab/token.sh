#!/bin/sh
# token.sh: create a "deploy-bot" Grafana service account (Editor) and print a token for it.
# deploy.sh uses that token to add a "deployed" annotation to the dashboards.
# Use it like this:   export GRAFANA_TOKEN=$(./token.sh)
# The admin login is the FAKE lab password from compose.yaml. In real life this token is a CI secret, never in Git.
set -eu
G=http://admin:fake-admin-pass-123@localhost:3000
ID=$(curl -s -X POST "$G/api/serviceaccounts" -H "Content-Type: application/json" \
  -d '{"name": "deploy-bot", "role": "Editor"}' | jq -r .id)
curl -s -X POST "$G/api/serviceaccounts/$ID/tokens" -H "Content-Type: application/json" \
  -d '{"name": "deploy"}' | jq -r .key
