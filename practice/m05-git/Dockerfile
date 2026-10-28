# syntax=docker/dockerfile:1
# DevOps course, Module 05 practice sheet: the Git rescue lab.
# Ubuntu 24.04 with Git 2.43 from Ubuntu's own packages. Two laptops in one container: asha and priya.
# Every scenario gets its own clone of allcsvideos-ops (~/rescue/NN-...) and its own copy of the team's
# origin (/srv/git/sNN/allcsvideos-ops.git), so a mistake in one scenario never spills into another.
# All history is built FOR THE PRACTICE with fixed names and dates, so the commit hashes are the same for everyone.
# Everything below is broken ON PURPOSE. Reading this file spoils the scenarios.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive TZ=Asia/Kolkata
RUN apt-get update && apt-get install -y --no-install-recommends git tzdata nano less ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime && echo Asia/Kolkata > /etc/timezone \
    && (userdel -r ubuntu 2>/dev/null || true) \
    && for u in asha priya; do useradd -m -s /bin/bash $u; done

# ---- the first version of the repository: README and a compact copy of the hc toolkit from Module 3 ----
COPY <<'EOF' /opt/lab/README.md
# allcsvideos-ops

Scripts and configs that run the allcsvideos platform.

- `hc/`: the server helth check, from the Module 3 build
EOF
COPY <<'EOF' /opt/lab/hc/hc.conf
# /etc/hc/hc.conf: settings for hc on this server.
# KEY=value, no spaces around =, no quotes. Read as data, never run.
DISK_WARN=80
DISK_CRIT=90
# memory: alert when this percent or less is still available
MEM_WARN=20
MEM_CRIT=10
# the 1-minute load average, divided by the number of CPUs
LOAD_WARN=1.5
LOAD_CRIT=3
MOUNTS=/ /data
SERVICES=nginx allcsvideos-api
HTTP_TIMEOUT=3
# a real chat webhook URL is a secret: keep this file mode 640
WEBHOOK_URL=http://hooks:9000/hc
EOF
COPY --chmod=755 <<'EOF' /opt/lab/hc/bin/hc
#!/usr/bin/env bash
# hc: the allcsvideos server health check (a compact copy for the Git practice lab)
set -uo pipefail
readonly VERSION=1.1.0
here=$(cd "$(dirname "$0")/.." && pwd)
source "$here/lib/checks.sh"
conf=$here/hc.conf
case ${1:-} in
  --version) echo "hc $VERSION"; exit 0 ;;
  -c) conf=$2 ;;
esac
load_config "$conf" || exit 3
echo "hc: config ok"
EOF
COPY <<'EOF' /opt/lab/hc/lib/checks.sh
# checks.sh: shared functions for hc and its tests
KNOWN=(DISK_WARN DISK_CRIT MEM_WARN MEM_CRIT LOAD_WARN LOAD_CRIT MOUNTS SERVICES HTTP_TIMEOUT WEBHOOK_URL)

load_config() {   # load_config FILE: read KEY=value lines, refuse unknown settings
  local key
  while IFS='=' read -r key _; do
    [[ -z $key || $key == \#* ]] && continue
    if [[ " ${KNOWN[*]} " != *" $key "* ]]; then
      echo "hc: unknown setting $key" >&2
      return 1
    fi
  done < "$1"
}

rate() {   # rate VALUE WARN CRIT: prints OK, WARN or CRIT
  if (( $1 >= $3 )); then echo CRIT
  elif (( $1 >= $2 )); then echo WARN
  else echo OK; fi
}
EOF
COPY --chmod=755 <<'EOF' /opt/lab/hc/tests/run.sh
#!/usr/bin/env bash
# run.sh: hc's tests. Exits 0 only when every test passes.
cd "$(dirname "$0")/.." || exit 1
source lib/checks.sh
pass=0 fail=0
check() {   # check NAME EXPECTED ACTUAL
  if [[ $2 == "$3" ]]; then pass=$((pass + 1))
  else echo "FAIL  $1: expected $2, got $3"; fail=$((fail + 1)); fi
}
check "rate 79 is OK" OK "$(rate 79 80 90)"
check "rate 80 is WARN" WARN "$(rate 80 80 90)"
check "rate 90 is CRIT" CRIT "$(rate 90 80 90)"
check "rate 95 is CRIT" CRIT "$(rate 95 80 90)"
check "hc.conf loads" ok "$(bin/hc > /dev/null 2>&1 && echo ok || echo failed)"
echo "$pass passed, $fail failed"
(( fail == 0 ))
EOF

# ---- three weeks of team history on main (Nov 2 - 19, 2026, IST), then one broken repository per scenario ----
RUN <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
git config --global init.defaultBranch main
git config --global advice.detachedHead false
who(){ local n; case $1 in asha) n=Asha;; priya) n=Priya;; rahul) n=Rahul;; esac
  export GIT_AUTHOR_NAME=$n GIT_AUTHOR_EMAIL=$1@example.com GIT_COMMITTER_NAME=$n GIT_COMMITTER_EMAIL=$1@example.com; }
at(){ export GIT_AUTHOR_DATE="$1 +0530" GIT_COMMITTER_DATE="$1 +0530"; }
c(){ who "$1"; at "$2"; git add -A; git commit -q -m "$3"; }   # c USER 'YYYY-MM-DD HH:MM' 'message'
ap(){ printf "$2" >> "$1"; }                                   # ap FILE 'text': append to a file

# ---- the team's history, pushed to the original origin
git init -q --bare /srv/git/base.git
mkdir /root/team && cd /root/team && git init -q && cp -a /opt/lab/. . && git remote add origin /srv/git/base.git
c asha  '2026-11-02 10:00' 'hc: import the toolkit from Module 3'
sed -i 's/^SERVICES=.*/SERVICES=nginx allcsvideos-api redis/' hc/hc.conf
c rahul '2026-11-03 11:05' 'hc.conf: also check redis'
sed -i 's/^readonly VERSION=1.1.0/readonly VERSION=1.2.0/' hc/bin/hc
c asha  '2026-11-04 16:30' 'hc: version 1.2.0'
at '2026-11-04 16:35'; who asha; git tag -a v1.2.0 -m 'hc 1.2.0'; git branch release/1.2
ap README.md '\n## Tests\n\nRun `hc/tests/run.sh` before every push. It exits 0 only when every test passes.\n'
c priya '2026-11-05 10:20' 'README: how to run the tests'
sed -i 's/^LOAD_WARN=1.5/LOAD_WARN=2/' hc/hc.conf
c rahul '2026-11-06 09:50' 'hc.conf: warn at load 2 per CPU'
sed -i 's/ WEBHOOK_URL)/ WEBHOOK_URL CERT_DAYS)/' hc/lib/checks.sh
ap hc/hc.conf '# TLS certificates: WARN when one expires in this many days or fewer\nCERT_DAYS=14\n'
c asha  '2026-11-09 11:15' 'checks: add the CERT_DAYS setting'
sed -i 's/^check "rate 79 is OK"/check "rate 0 is OK" OK "$(rate 0 80 90)"\n&/' hc/tests/run.sh
c priya '2026-11-10 15:40' 'tests: rate 0 is OK'
perl -0pi -e 's/rate\(\) \{   # rate VALUE WARN CRIT: prints OK, WARN or CRIT\n  if \(\( \$1 >= \$3 \)\); then echo CRIT\n  elif \(\( \$1 >= \$2 \)\); then echo WARN/rate() {   # rate VALUE WARN CRIT: prints OK, WARN or CRIT\n  local v=\$1 warn=\$2 crit=\$3\n  if (( v > crit )); then echo CRIT\n  elif (( v >= warn )); then echo WARN/' hc/lib/checks.sh
c rahul '2026-11-11 17:05' 'checks: tidy rate()'
ap README.md '\n## Settings\n\n`CERT_DAYS`: WARN when a TLS certificate expires in this many days or fewer.\n'
c asha  '2026-11-12 10:10' 'README: document CERT_DAYS'
sed -i 's|^MOUNTS=.*|MOUNTS=/ /data /srv|' hc/hc.conf
c priya '2026-11-13 12:30' 'hc.conf: check /srv too'
sed -i 's/^    \[\[ -z \$key || \$key == \\#\* \]\] && continue$/    [[ $key =~ ^[[:space:]]*(#|$) ]] \&\& continue   # blank lines and comments, even indented/' hc/lib/checks.sh
grep -q 'even indented' hc/lib/checks.sh
c rahul '2026-11-16 10:45' 'checks: allow indented comments in hc.conf'
sed -i 's/^readonly VERSION=1.2.0/readonly VERSION=1.3.0/' hc/bin/hc
c asha  '2026-11-17 16:00' 'hc: version 1.3.0'
at '2026-11-17 16:05'; who asha; git tag -a v1.3.0 -m 'hc 1.3.0'
ap README.md '\n## Releases\n\nReleases are tagged `vMAJOR.MINOR.PATCH` (semver). Fixes for a shipped version go to its `release/X.Y` branch.\n'
c priya '2026-11-19 11:00' 'README: the release process'
git push -q origin main release/1.2 v1.2.0 v1.3.0

# ---- helpers for the scenarios
for n in $(seq -w 1 18); do mkdir -p /srv/git/s$n && cp -a /srv/git/base.git /srv/git/s$n/allcsvideos-ops.git; done
clone(){ git clone -q /srv/git/s$1/allcsvideos-ops.git /home/$2/rescue/$1-$3 && cd /home/$2/rescue/$1-$3; }   # clone NN USER SLUG
team(){ rm -rf /root/t && git clone -q /srv/git/s$1/allcsvideos-ops.git /root/t && cd /root/t; }               # a teammate's clone

# ---- 01 (priya): two commits on main that belong on a branch
clone 01 priya wrong-branch
sed -i 's/^DISK_CRIT=90/DISK_CRIT=95/' hc/hc.conf
c priya '2026-11-23 10:05' 'hc.conf: raise DISK_CRIT to 95'
ap README.md '\n## Disk thresholds\n\nThe data volume is 2 TB: at 90%% there are still 200 GB free, so CRIT is 95.\n'
c priya '2026-11-23 10:12' 'README: explain the disk thresholds'

# ---- 02 (priya): a commit made in detached HEAD, then left behind
clone 02 priya detached-head
git checkout -q v1.2.0
ap README.md '\nOwner: the platform team (#platform on chat).\n'
c priya '2026-11-23 11:00' 'README: add the owner'
git switch -q main 2>/dev/null

# ---- 03 (asha): a typo in the last commit message, and a forgotten file
clone 03 asha amend
sed -i 's/^MEM_WARN=20/MEM_WARN=15/' hc/hc.conf
git add hc/hc.conf; who asha; at '2026-11-23 12:00'; git commit -q -m 'hc.conf: warn at 15% memroy left'
ap README.md '\n## Memory\n\nhc warns when 15%% of memory or less is available, and goes critical at 10%%.\n'

# ---- 04 (asha): reset --hard HEAD~3 instead of HEAD~1
clone 04 asha reset-too-far
sed -i 's/^LOAD_CRIT=3/LOAD_CRIT=4/' hc/hc.conf
c asha '2026-11-23 14:00' 'hc.conf: CRIT at load 4 per CPU'
ap README.md '\n## Load\n\nhc warns at a load of 2 per CPU, and goes critical at 4.\n'
c asha '2026-11-23 14:10' 'README: document the load thresholds'
sed -i 's|^MOUNTS=.*|MOUNTS=/ /data /srv /tmp|' hc/hc.conf
c asha '2026-11-23 14:25' 'experiment: check /tmp too'
git reset -q --hard HEAD~3

# ---- 05 (asha): a branch deleted with -D, never pushed
clone 05 asha deleted-branch
git switch -q -c spike/json-alerts
cat > hc/lib/json.sh <<'TXT'
# json.sh: format an alert as one line of JSON
alert_json() {   # alert_json STATUS CHECK DETAIL
  printf '{"status":"%s","check":"%s","detail":"%s"}\n' "$1" "$2" "$3"
}
TXT
c asha '2026-11-23 15:00' 'spike: format alerts as JSON'
sed -i 's/{"status":"%s"/{"host":"%s","status":"%s"/; s/ "\$1" "\$2" "\$3"$/ "$(hostname)" "$1" "$2" "$3"/' hc/lib/json.sh
c asha '2026-11-23 15:40' 'spike: add the host name to JSON alerts'
git switch -q main; git branch -q -D spike/json-alerts

# ---- 06 (asha): an old stash, work in progress with a new file, and an urgent request
clone 06 asha stash
sed -i 's/^HTTP_TIMEOUT=3/HTTP_TIMEOUT=2/' hc/hc.conf
who asha; at '2026-11-17 15:00'; git stash push -q -m 'try HTTP_TIMEOUT=2'
git switch -q -c feature/check-docker
sed -i 's/^SERVICES=.*/SERVICES=nginx allcsvideos-api redis docker/' hc/hc.conf
c asha '2026-11-23 16:00' 'hc.conf: also check the docker service'
sed -i 's|^MOUNTS=.*|MOUNTS=/ /data /srv /var/lib/docker|' hc/hc.conf
printf 'MOUNTS=/var/lib/docker\nSERVICES=docker\n' > hc/tests/docker.conf

# ---- 07 (asha): stopped in the middle of a merge with a conflict
clone 07 asha merge-conflict
git switch -q -c tune/disk-thresholds
sed -i 's/^DISK_CRIT=90/DISK_CRIT=95/' hc/hc.conf
c asha '2026-11-24 10:30' 'hc.conf: CRIT at 95% disk'
team 07
sed -i 's/^DISK_WARN=80/DISK_WARN=85/' hc/hc.conf
c priya '2026-11-24 11:00' 'hc.conf: WARN at 85% disk'
sed -i 's|^- `hc/`: the server helth check, from the Module 3 build|&. The data volume on every server is 2 TB.|' README.md
c rahul '2026-11-24 11:20' 'README: mention the data volume'
git push -q origin main
cd /home/asha/rescue/07-merge-conflict && git fetch -q && (git merge origin/main >/dev/null 2>&1 || true)

# ---- 08 (priya): a pull --rebase that went wrong, half edited
clone 08 priya bad-rebase
git switch -q -c feature/cert-check
sed -i 's/^CERT_DAYS=14/CERT_DAYS=21/' hc/hc.conf
ap hc/lib/checks.sh '\ncheck_cert() {   # check_cert HOST: WARN when the TLS certificate of HOST expires soon\n  local end days\n  end=$(openssl s_client -connect "$1:443" -servername "$1" </dev/null 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)\n  days=$(( ($(date -d "$end" +%%s) - $(date +%%s)) / 86400 ))\n  if (( days <= CERT_DAYS )); then echo WARN; else echo OK; fi\n}\n'
c priya '2026-11-24 10:00' 'checks: add check_cert'
ap README.md '\n`check_cert HOST` warns when the certificate of HOST expires in `CERT_DAYS` days or fewer.\n'
c priya '2026-11-24 10:40' 'README: document check_cert'
sed -i 's/^check "rate 95 is CRIT".*/&\ncheck "rate 100 is CRIT" CRIT "$(rate 100 80 90)"/' hc/tests/run.sh
c priya '2026-11-24 11:10' 'tests: rate 100 is CRIT'
team 08
sed -i 's/^CERT_DAYS=14/CERT_DAYS=30/' hc/hc.conf
c asha '2026-11-24 12:00' 'hc.conf: CERT_DAYS 30, the renewal window'
git push -q origin main
cd /home/priya/rescue/08-bad-rebase && who priya && (git pull -q --rebase origin main >/dev/null 2>&1 || true)
sed -i '/^<<<<<<< /d; s/^CERT_DAYS=30$/CERT_DAYS=25/' hc/hc.conf
git add hc/hc.conf

# ---- 09 (priya): four commits for one change, before the pull request
clone 09 priya squash
git switch -q -c feature/cert-hosts
sed -i 's/ CERT_DAYS)/ CERT_DAYS CERT_HOSTS)/' hc/lib/checks.sh
ap hc/hc.conf 'CERT_HOSTS=allcsvideos.com api.allcsvideos.com\n'
c priya '2026-11-24 14:00' 'checks: add CERT_HOSTS'
ap README.md '\n`CERT_HOSTS`: the hosts whose certifcates hc checks.\n'
c priya '2026-11-24 14:20' 'wip'
sed -i 's/certifcates/certificates/' README.md
c priya '2026-11-24 14:22' 'fix typo'
sed -i 's/^`CERT_HOSTS`: the hosts whose certificates hc checks./&, separated by spaces/' README.md
c priya '2026-11-24 14:35' 'wip again'

# ---- 10 (asha): a bad commit, already pushed to main and pulled by the team
clone 10 asha pushed-bad-commit
team 10
sed -i 's/^HTTP_TIMEOUT=3/HTTP_TIMEOUT_SECONDS=3/' hc/hc.conf
c priya '2026-11-25 09:40' 'hc.conf: rename HTTP_TIMEOUT to HTTP_TIMEOUT_SECONDS'
git push -q origin main
cd /home/asha/rescue/10-pushed-bad-commit && git pull >/dev/null 2>&1

# ---- 11 (asha): a webhook token in the last commit, not pushed yet (a FAKE demo token)
clone 11 asha secret
git switch -q -c feature/chat-alerts
sed -i 's|^WEBHOOK_URL=.*|WEBHOOK_URL=https://chat.example.com/hooks/allcs-alerts?token=demo-token-123|' hc/hc.conf
ap README.md '\n## Alerts\n\nhc posts WARN and CRIT alerts to the team chat.\n'
c asha '2026-11-25 11:00' 'notify: send alerts to the team chat'

# ---- 12 (priya): Asha rebased a shared branch and force-pushed it
clone 12 priya force-push
git switch -q -c feature/notify-v2
sed -i 's/ CERT_DAYS)/ CERT_DAYS NOTIFY_V2)/' hc/lib/checks.sh
ap hc/hc.conf 'NOTIFY_V2=off\n'
c priya '2026-11-24 10:00' 'notify: NOTIFY_V2 setting, off by default'
ap hc/lib/checks.sh '\nnotify_url() {   # notify_url SEVERITY: the webhook for that severity\n  echo "$WEBHOOK_URL"\n}\n'
c priya '2026-11-24 10:30' 'notify: pick the webhook by severity'
git push -q -u origin feature/notify-v2
team 12
git switch -q feature/notify-v2
ap README.md '\n`NOTIFY_V2`: the new alert path, `off` until it is ready.\n'
c asha '2026-11-24 14:00' 'README: document NOTIFY_V2'
git push -q
cd /home/priya/rescue/12-force-push && git pull >/dev/null 2>&1
sed -i 's/^  echo "\$WEBHOOK_URL"$/  echo "hc: alert via $WEBHOOK_URL" >\&2\n&/' hc/lib/checks.sh
c priya '2026-11-25 09:30' 'notify: log which webhook is used'
cd /root/t && git switch -q main
sed -i 's/^MEM_CRIT=10/MEM_CRIT=5/' hc/hc.conf
c rahul '2026-11-25 10:00' 'hc.conf: MEM_CRIT 5'
git push -q origin main
git switch -q feature/notify-v2 && who asha && at '2026-11-25 10:30' && git rebase -q main && git push -q --force

# ---- 13 (priya): CRLF line endings from a Windows editor, and a .gitattributes that covers too little
clone 13 priya line-endings
team 13
sed -i 's/$/\r/' hc/bin/hc hc/lib/checks.sh hc/tests/run.sh
c rahul '2026-11-25 16:00' 'hc: tidy up the scripts'
printf '# shell scripts always use LF line endings\n*.sh text eol=lf\n' > .gitattributes
git add .gitattributes; who asha; at '2026-11-26 09:00'; git commit -q -m 'Add .gitattributes: shell scripts use LF'
git push -q origin main
cd /home/priya/rescue/13-line-endings && git pull >/dev/null 2>&1

# ---- 14 (asha) and 15 (asha): clean clones; the problem is already in the history
clone 14 asha hotfix
clone 15 asha bisect

# ---- 16 (priya): a force-push, a failed pull, and then a reset --hard that dropped two commits
clone 16 priya lost-after-force-push
git switch -q -c feature/alert-routing
sed -i 's/ CERT_DAYS)/ CERT_DAYS ROUTE_CRIT)/' hc/lib/checks.sh
ap hc/hc.conf '# where CRIT alerts go: chat or pager\nROUTE_CRIT=pager\n'
c priya '2026-11-24 10:00' 'notify: ROUTE_CRIT setting'
git push -q -u origin feature/alert-routing
team 16
git switch -q feature/alert-routing
ap README.md '\n`ROUTE_CRIT`: where CRIT alerts go, `chat` or `pager`.\n'
c asha '2026-11-24 14:00' 'README: document ROUTE_CRIT'
git push -q
cd /home/priya/rescue/16-lost-after-force-push && git pull >/dev/null 2>&1
ap hc/lib/checks.sh '\nroute() {   # route SEVERITY: where an alert of that severity goes\n  if [[ $1 == CRIT ]]; then echo "${ROUTE_CRIT:-chat}"; else echo chat; fi\n}\n'
c priya '2026-11-25 09:30' 'notify: route CRIT alerts to the pager'
sed -i 's/^check "hc.conf loads".*/check "WARN goes to chat" chat "$(route WARN)"\n&/' hc/tests/run.sh
c priya '2026-11-25 09:50' 'tests: WARN alerts go to chat'
cd /root/t && git switch -q main
sed -i 's/^MEM_CRIT=10/MEM_CRIT=5/' hc/hc.conf
c rahul '2026-11-25 10:00' 'hc.conf: MEM_CRIT 5'
git push -q origin main
git switch -q feature/alert-routing && who asha && at '2026-11-25 10:30' && git rebase -q main && git push -q --force
cd /home/priya/rescue/16-lost-after-force-push && (git pull >/dev/null 2>&1 || true) && git reset -q --hard origin/feature/alert-routing

# ---- 17 (asha): a branch to clean up before review: a token in the middle commit, and a wip
clone 17 asha ready-for-review
git switch -q -c feature/team-webhook
sed -i 's/ CERT_DAYS)/ CERT_DAYS WEBHOOK_TEAM)/' hc/lib/checks.sh
c asha '2026-11-26 10:00' 'checks: add WEBHOOK_TEAM to the known settings'
ap hc/hc.conf '# WARN alerts go to the team channel\nWEBHOOK_TEAM=https://chat.example.com/hooks/allcs-team?token=demo-token-456\n'
c asha '2026-11-26 10:20' 'hc.conf: send WARN alerts to the team channel'
ap README.md '\n`WEBHOOK_TEAM`: WARN alerts go to the team channel; CRIT alerts page the on-call person.\n'
c asha '2026-11-26 10:45' 'wip'

# ---- 18 (asha): ship the fix for 1.3
clone 18 asha ship-1.3.1

# ---- hand everything to its owner
cd / && rm -rf /root/t /root/team /srv/git/base.git /opt/lab
for n in $(seq -w 1 18); do
  o=$(ls -d /home/*/rescue/$n-* | cut -d/ -f3)
  chown -R $o:$o /srv/git/s$n /home/$o/rescue
done
EOF

# ---- each laptop's Git identity
RUN for u in asha priya; do n=$(echo $u | sed 's/./\U&/'); \
      su $u -c "git config --global user.name $n && git config --global user.email $u@example.com \
        && git config --global init.defaultBranch main && git config --global core.editor nano"; done

CMD ["sleep", "infinity"]
