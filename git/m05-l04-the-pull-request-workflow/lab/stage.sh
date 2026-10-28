#!/usr/bin/env bash
# stage.sh <step> [PR] - what the video does in the web UI or off screen, done through Gitea's REST API and tea.
#   protect        Asha's branch protection for main (files/protect-main.json); same switches as the settings page
#   review [3]     Rahul's review of Priya's pull request: request changes, with two labelled line comments
#   update [3]     Priya's "Update branch by merge" button: merges main into her pull request branch
#   version-pr     the version bump to 1.3.0 through its own pull request (#4): branch, PR, CI, Rahul approves, Asha merges
#   docs-pr        Priya's docs pull request for CERT_HOSTS (#5): branch, PR, CI, Rahul approves, Priya merges
set -euo pipefail
cd "$(dirname "$0")"
C=git-team
R=/repos/allcsvideos/allcsvideos-ops
api() { local u=$1 m=$2 p=$3 d=${4:-}
  docker exec -i $C runuser -u "$u" -- sh -c "curl -s -X $m -H 'Content-Type: application/json' -H \"Authorization: token \$(cat ~/.gitea-token)\" http://gitea:3000/api/v1$p ${d:+-d @-}" <<<"$d"; }
as() { docker exec -i -u "$1" -w "/home/$1/allcsvideos-ops" $C bash -se; }
case "${1:-}" in
protect)
  api asha POST $R/branch_protections "$(cat ../files/protect-main.json)" | docker exec -i $C jq -c '{rule_name,enable_push,required_approvals,enable_status_check,status_check_contexts,block_on_codeowner_reviews,block_on_outdated_branch,dismiss_stale_approvals,block_admin_merge_override}' ;;
review)
  pr=${2:-3}
  ln=$(docker exec -u priya $C sh -c "cd ~/allcsvideos-ops && git show origin/feature/cert-hosts:hc/hc.conf | grep -n '^CERT_HOSTS' | cut -d: -f1")
  api rahul POST $R/pulls/$pr/reviews "{\"event\":\"REQUEST_CHANGES\",\"body\":\"praise: small and easy to review, thanks. One blocking issue below.\",\"comments\":[{\"path\":\"hc/hc.conf\",\"new_position\":$ln,\"body\":\"issue (blocking): CI is red. CERT_HOSTS is not in KEYS in hc/lib/checks.sh, so hc would stop on every server with unknown setting, like the rename on main. Please add it there and to the test configs.\"},{\"path\":\"hc/hc.conf\",\"new_position\":$ln,\"body\":\"question (non-blocking): should www.allcsvideos.com be on the list too?\"}]}" | docker exec -i $C jq -r '"review \(.id): \(.state)"' ;;
update)
  api priya POST "$R/pulls/${2:-3}/update?style=merge"; echo "main merged into the pull request branch" ;;
version-pr)
  as asha <<'EOF'
git switch -q main && git pull -q
git switch -q -c chore/version-1.3.0 && sed -i 's/^readonly VERSION=1.2.0$/readonly VERSION=1.3.0/' hc/bin/hc && git commit -qam 'hc: version 1.3.0' && git push -q -u origin chore/version-1.3.0
tea pulls create --title 'hc: version 1.3.0' --description 'Version bump for the 1.3.0 release: CERT_HOSTS, the NOTIFY_V2 flag, the 30 s timer spread.'
EOF
  pr=$(api asha GET "$R/pulls?state=open" | docker exec -i $C jq -r '.[] | select(.head.ref=="chore/version-1.3.0") | .number')
  bash ./ci.sh "$pr" | tail -1
  as rahul <<EOF
tea pulls approve $pr 'Ready to release.'
EOF
  as asha <<EOF
tea pulls merge --style squash $pr && tea pulls clean $pr && git pull -q && git log --oneline -1
EOF
  ;;
docs-pr)
  as priya <<'EOF'
git switch -q main && git pull -q && git switch -q -c docs/cert-hosts
printf '\n`CERT_HOSTS`: the public hosts whose TLS certificates hc checks (space-separated).\n' >> hc/README.md
git commit -qam 'README: document CERT_HOSTS' && git push -q -u origin docs/cert-hosts
tea pulls create --title 'README: document CERT_HOSTS' --description 'Docs only. Follow-up to #3.'
EOF
  pr=$(api priya GET "$R/pulls?state=open" | docker exec -i $C jq -r '.[] | select(.head.ref=="docs/cert-hosts") | .number')
  bash ./ci.sh "$pr" | tail -1
  as rahul <<EOF
tea pulls approve $pr 'Docs look right.'
EOF
  as priya <<EOF
tea pulls merge --style squash $pr && tea pulls clean $pr && git pull -q && git log --oneline -1
EOF
  ;;
*) sed -n '2,7p' "$0"; exit 1 ;;
esac
