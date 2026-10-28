#!/usr/bin/env bash
# forge.sh: sets up Gitea for the lesson, after up.sh and after priya and rahul exist (README step 2).
#  - one access token per account, generated inside the lab and written straight into that user's ~/.git-credentials,
#    ~/.gitea-token and tea login inside git-team (never printed)
#  - organisation allcsvideos (owner asha), team devs (write) with priya and rahul, ci-bot as a write collaborator,
#    and an empty repository allcsvideos/allcsvideos-ops
set -euo pipefail
G=gitea C=git-team
for u in asha priya rahul ci-bot; do
  tok=$(docker exec -u git $G gitea admin user generate-access-token --username $u --token-name lab --scopes all --raw)
  h=/home/$u; [ $u = ci-bot ] && h=/root
  docker exec $C sh -c "printf 'http://%s:%s@gitea:3000\n' '$u' '$tok' > $h/.git-credentials && chmod 600 $h/.git-credentials && echo '$tok' > $h/.gitea-token && chmod 600 $h/.gitea-token"
  if [ $u != ci-bot ]; then
    docker exec $C chown $u:$u $h/.git-credentials $h/.gitea-token
    docker exec -u $u $C sh -c 'tea login add --name gitea --url http://gitea:3000 --token "$(cat ~/.gitea-token)" >/dev/null && tea login default gitea >/dev/null'
  fi
done
unset tok
# api USER METHOD PATH [JSON]: a REST call to Gitea as that user
api() { local u=$1 m=$2 p=$3 d=${4:-}
  docker exec -i $C runuser -u "$u" -- sh -c "curl -s -X $m -H 'Content-Type: application/json' -H \"Authorization: token \$(cat ~/.gitea-token)\" http://gitea:3000/api/v1$p ${d:+-d @-}" <<<"$d"; }
api asha POST /orgs '{"username":"allcsvideos","full_name":"allcsvideos.com","visibility":"public"}' >/dev/null
tid=$(api asha POST /orgs/allcsvideos/teams '{"name":"devs","permission":"write","units":["repo.code","repo.issues","repo.pulls","repo.releases"],"includes_all_repositories":true}' | docker exec -i $C jq .id)
for u in priya rahul; do api asha PUT "/teams/$tid/members/$u" >/dev/null; done
api asha POST /orgs/allcsvideos/repos '{"name":"allcsvideos-ops","description":"Ops scripts and configs for allcsvideos.com","default_branch":"main"}' | docker exec -i $C jq -r .full_name
api asha PUT /repos/allcsvideos/allcsvideos-ops/collaborators/ci-bot '{"permission":"write"}' >/dev/null
echo "forge ready: http://localhost:3000/allcsvideos/allcsvideos-ops"
