#!/usr/bin/env bash
# forge.sh - lab accounts (FAKE passwords), one token per account, the organisation allcsvideos, team devs
# (write: priya and backstage-bot). backstage-bot is the account the portal uses to create repositories.
#   asha           asha@example.com            site admin, owns the allcsvideos organisation (platform team)
#   priya          priya@example.com           developer (team devs: write, can create org repos)
#   backstage-bot  backstage-bot@example.com   the portal's account (team devs)
# Tokens are written to lab/secrets/ (git-ignored) and never printed.
set -euo pipefail
cd "$(dirname "$0")"
gx(){ docker exec -u git gitea gitea "$@"; }
gx admin user create --username asha  --email asha@example.com  --password fake-lab-pass-asha  --admin --must-change-password=false --fullname Asha >/dev/null
gx admin user create --username priya --email priya@example.com --password fake-lab-pass-priya --must-change-password=false --fullname Priya >/dev/null
gx admin user create --username backstage-bot --email backstage-bot@example.com --password fake-lab-pass-backstage-bot --must-change-password=false --fullname 'Backstage (lab bot)' >/dev/null
mkdir -p secrets; chmod 700 secrets
gx admin user generate-access-token --username asha --token-name lab --scopes all --raw > secrets/asha.token
# the portal's token: a file that only the Backstage container mounts
gx admin user generate-access-token --username backstage-bot --token-name portal --scopes write:repository,write:organization,read:user --raw > secrets/backstage-bot.token
chmod 600 secrets/*.token
api(){ curl -s -X "$1" -H 'Content-Type: application/json' -H "Authorization: token $(cat secrets/asha.token)" "http://localhost:3000/api/v1$2" ${3:+-d "$3"}; }
api POST /orgs '{"username":"allcsvideos","full_name":"allcsvideos.com","visibility":"public"}' >/dev/null
td=$(api POST /orgs/allcsvideos/teams '{"name":"devs","permission":"write","units":["repo.code","repo.issues","repo.pulls","repo.actions"],"includes_all_repositories":true,"can_create_org_repo":true}' | jq .id)
api PUT /teams/$td/members/priya >/dev/null
api PUT /teams/$td/members/backstage-bot >/dev/null
echo "forge ready"
