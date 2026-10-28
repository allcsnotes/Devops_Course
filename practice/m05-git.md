# Module 05 · Practice Sheet: 15 Git Rescue Scenarios

It's Monday morning, the week after the hc 1.3.0 release, and the team chat is busy. Priya's first message arrives at 9:12:

> Help. I committed to main by mistake, my fix from Friday has vanished, and Git now says something about divergent branches. Is it safe to just delete the folder and clone again?

It isn't. Deleting the folder throws away the one place where the lost work still lives. Before lunch, Asha and Rahul have their own "help, I broke it" messages too.

In this practice sheet you get both laptops, Asha's and Priya's, in one Docker container on your machine. On them are 18 copies of the team's `allcsvideos-ops` repository, each one broken in its own way, for real. You rescue each one with only the tools from Module 5.

**How to work:**
- You need Docker Desktop, as set up in Module 01. Nothing else is installed on your machine.
- Each scenario has its **own folder**, `~/rescue/NN-...`, with its own clone, and its **own origin**, `/srv/git/sNN/allcsvideos-ops.git`. A mistake in one scenario never spills into another, so you can do them in any order. They're sorted easy to hard, and each one says which lesson it uses: L01 how Git really works, L02 branching strategies, L03 merge, rebase and fixing mistakes, L04 the pull-request workflow.
- Each scenario says **whose laptop** it's on. Asha's are in `/home/asha/rescue`, Priya's in `/home/priya/rescue`: log in as that person.
- Each scenario has a **hint** and an **answer**. Try it yourself first. Every answer was run in this exact lab, and the output under it is the **real output** (long output, like push progress, is trimmed with `…`).
- The team history was built **for this practice**, with names and dates set on purpose, so every commit that exists before you start has the **same hash on your machine** as in the answers (`499a94a` is always `README: the release process`). Commits **you** make get today's date, so their hashes differ: the answers say "yours will differ" where it matters. Transfer speeds and thread counts in push output differ too.
- Where an answer edits a file or a rebase to-do list, the sheet shows the edit as a one-line command (`sed`), so you can see exactly what changed. Doing the same edit in `nano` is just as good.
- The origins are plain bare repositories, like lessons 2 and 3: no branch protection. Where a scenario pushes to `main`, a team with a protected `main` (lesson 4) would push a branch and open a pull request instead.
- In the answers, `$` is the prompt of whoever's laptop it is. On your screen it reads `asha@lab:~/rescue/03-amend$` or `priya@lab:~/rescue/01-wrong-branch$`.
- Scenarios 16 to 18 are the final challenge: each one combines several rescues.
- The two webhook tokens in the lab are **fake demo values**, made only for this sandbox.

---

## Set up the rescue lab

**1. Save the Dockerfile.** This repository already has it: [`m05-git/Dockerfile`](m05-git/Dockerfile), so you can simply `cd practice/m05-git` and skip to step 2. (Or make an empty folder, for example `m05-lab`, and save the file below into it as `Dockerfile`.) It builds the history and breaks the repositories on purpose, so it **contains every answer**. Copy it without reading it.

<details>
<summary><b>Dockerfile (spoilers: copy it, don't read it)</b></summary>

```dockerfile
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
```

</details>

**2. Build the image** (under a minute the first time; it needs the internet for `apt`):

```bash
cd m05-lab        # in this repository: cd practice/m05-git
docker build --label course=devops -t m05lab-lab .
```

**3. Start the lab:**

```bash
docker run -d --name m05lab-lab --label course=devops --hostname lab m05lab-lab
```

**4. Log in.** Open one terminal for each laptop:

```bash
docker exec -it -u asha -w /home/asha m05lab-lab bash -l
docker exec -it -u priya -w /home/priya m05lab-lab bash -l
```

A few lab notes:
- Both laptops already have a Git identity (`Asha <asha@example.com>`, `Priya <priya@example.com>`), `main` as the default branch, and `nano` as the editor Git opens.
- `git log` and `git show` open long output in a pager: `q` quits.
- `ls ~/rescue` lists the scenario folders on that laptop. Start every scenario with `cd ~/rescue/NN-...`.
- **Start over** at any time: `docker rm -f m05lab-lab`, then the `docker run` again. That resets **every** scenario on both laptops to its broken state, so finish the ones you're in the middle of first.
- When you're done, clean up with the commands at the end of this sheet.

---

## The rescues

### 1 · Two commits on the wrong branch (L01, L03)
**On Priya's laptop**, `~/rescue/01-wrong-branch`.

> Priya, 9:12: I made two commits for my disk-thresholds fix, but I forgot to create the branch first. They're on main! Nothing is pushed yet.

Move both commits to a new branch called `fix/disk-thresholds`, put `main` back exactly where `origin/main` is, and push the branch.

<details>
<summary>Hint</summary>

A branch is only a name for a commit (lesson 1). So: create the new name **where you are now**, then move `main` back with `git reset --hard origin/main`. The commits stay safe, because the new branch still points at them. `git status -sb` shows how far ahead of `origin/main` you are.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/rescue/01-wrong-branch
$ git status -sb
## main...origin/main [ahead 2]
$ git log --oneline -3
387a266 (HEAD -> main) README: explain the disk thresholds
c85bc3c hc.conf: raise DISK_CRIT to 95
499a94a (origin/main, origin/HEAD) README: the release process
$ git branch fix/disk-thresholds
$ git reset --hard origin/main
HEAD is now at 499a94a README: the release process
$ git switch fix/disk-thresholds
Switched to branch 'fix/disk-thresholds'
$ git log --oneline --graph --all -4
* 387a266 (HEAD -> fix/disk-thresholds) README: explain the disk thresholds
* c85bc3c hc.conf: raise DISK_CRIT to 95
* 499a94a (origin/main, origin/HEAD, main) README: the release process
* 046a79a (tag: v1.3.0) hc: version 1.3.0
$ git status -sb
## fix/disk-thresholds
$ git push -u origin fix/disk-thresholds
…
To /srv/git/s01/allcsvideos-ops.git
 * [new branch]      fix/disk-thresholds -> fix/disk-thresholds
branch 'fix/disk-thresholds' set up to track 'origin/fix/disk-thresholds'.
```

**Why it works:** `git branch` wrote a new 41-byte name pointing at `387a266`, and `reset --hard` moved only the name `main`. No commit was copied, changed or lost, and the hashes are the same before and after. This is safe only because nothing was pushed: `main` on origin never had those commits.

</details>

### 2 · The commit that vanished (L01)
**On Priya's laptop**, `~/rescue/02-detached-head`.

> Priya, 9:20: On Friday I checked out v1.2.0 to look at the old README, added an owner line, and committed. Then I switched back to main. Now my commit isn't in git log, not even with --all. Where did it go?

Find the lost commit and give it a branch called `readme-owner`, so it can't get lost again.

<details>
<summary>Hint</summary>

Checking out a tag puts you in **detached HEAD**: new commits are pointed at by `HEAD` alone, and switching away leaves them with no name. `git log --all` starts only from names, so it can't see the commit. `git reflog` lists everywhere `HEAD` has been, named or not. `git branch <name> <hash>` gives a commit a name.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/rescue/02-detached-head
$ git status
On branch main
Your branch is up to date with 'origin/main'.

nothing to commit, working tree clean
$ git log --all --oneline | grep -c owner
0
$ git reflog -4
499a94a (HEAD -> main, origin/main, origin/HEAD) HEAD@{0}: checkout: moving from 238e21539d14cd46894874762f52a9c67e6b837d to main
238e215 HEAD@{1}: commit: README: add the owner
9b9919e (tag: v1.2.0, origin/release/1.2) HEAD@{2}: checkout: moving from main to v1.2.0
499a94a (HEAD -> main, origin/main, origin/HEAD) HEAD@{3}: clone: from /srv/git/s02/allcsvideos-ops.git
$ git branch readme-owner 238e215
$ git log --oneline --graph --all -6
* 238e215 (readme-owner) README: add the owner
| * 499a94a (HEAD -> main, origin/main, origin/HEAD) README: the release process
| * 046a79a (tag: v1.3.0) hc: version 1.3.0
| * b1026bb checks: allow indented comments in hc.conf
| * a98fe6d hc.conf: check /srv too
| * c6814ba README: document CERT_DAYS
$ git log --oneline -2 readme-owner
238e215 (readme-owner) README: add the owner
9b9919e (tag: v1.2.0, origin/release/1.2) hc: version 1.2.0
```

Read the reflog from the bottom up: the clone, the checkout of `v1.2.0`, Priya's commit `238e215`, and the switch back to main, which names the abandoned commit by its full hash.

**Why it works:** the commit was never deleted. It was only unreachable from every name, and the reflog keeps unreachable commits for 30 days by default. One `git branch` makes it reachable again. Next time, start experiments with `git switch -c`, and the commit has a branch from the start.

</details>

### 3 · Fix the last commit (L03)
**On Asha's laptop**, `~/rescue/03-amend`.

> Asha, 9:31 (to herself): Committed "memroy". And forgot the README section that goes with it. At least I haven't pushed.

Make the last commit's message read `hc.conf: warn at 15% memory left`, and put the README change into that **same** commit. Don't create a second commit.

<details>
<summary>Hint</summary>

`git status -sb` shows the unpushed commit (`ahead 1`) and the forgotten change. Stage the README, then `git commit --amend -m "…"`: amend replaces the last commit with a new one built from the index, with the new message.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/rescue/03-amend
$ git status -sb
## main...origin/main [ahead 1]
 M README.md
$ git log --oneline -2
12fe79d (HEAD -> main) hc.conf: warn at 15% memroy left
499a94a (origin/main, origin/HEAD) README: the release process
$ git add README.md
$ git commit --amend -m "hc.conf: warn at 15% memory left"
[main 9b8dd66] hc.conf: warn at 15% memory left
 Date: Mon Nov 23 12:00:00 2026 +0530
 2 files changed, 5 insertions(+), 1 deletion(-)
$ git show --stat --format='%h %s' HEAD
9b8dd66 hc.conf: warn at 15% memory left

 README.md  | 4 ++++
 hc/hc.conf | 2 +-
 2 files changed, 5 insertions(+), 1 deletion(-)
$ git status -sb
## main...origin/main [ahead 1]
```

The new hash (`9b8dd66` here) will differ on your machine: the amended commit gets today's date as its commit date. The `Date:` line is the **author** date, which amend keeps.

**Why it works:** amend never edits a commit; it writes a new one (new message, new tree) and moves `main` to it. Still `ahead 1`, not 2. Never amend a commit that's already pushed: that's rewriting shared history (scenario 10 shows the safe way).

</details>

### 4 · reset --hard went too far (L03)
**On Asha's laptop**, `~/rescue/04-reset-too-far`.

> Asha, 9:45: I wanted to drop my last commit, the /tmp experiment. I typed git reset --hard HEAD~3. Three commits are gone, and two of them were good.

Bring back the two good commits (`CRIT at load 4 per CPU` and the README for it) and drop only the experiment.

<details>
<summary>Hint</summary>

`git reflog` shows where `HEAD` was before the reset. `HEAD@{1}` means "one move ago". Reset back to it, then do the reset you meant: one commit, `HEAD~1`.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/rescue/04-reset-too-far
$ git log --oneline -2
499a94a (HEAD -> main, origin/main, origin/HEAD) README: the release process
046a79a (tag: v1.3.0) hc: version 1.3.0
$ git status -sb
## main...origin/main
$ git reflog -5
499a94a (HEAD -> main, origin/main, origin/HEAD) HEAD@{0}: reset: moving to HEAD~3
43b1870 HEAD@{1}: commit: experiment: check /tmp too
3747ba2 HEAD@{2}: commit: README: document the load thresholds
45acdf7 HEAD@{3}: commit: hc.conf: CRIT at load 4 per CPU
499a94a (HEAD -> main, origin/main, origin/HEAD) HEAD@{4}: clone: from /srv/git/s04/allcsvideos-ops.git
$ git reset --hard HEAD@{1}
HEAD is now at 43b1870 experiment: check /tmp too
$ git log --oneline -4
43b1870 (HEAD -> main) experiment: check /tmp too
3747ba2 README: document the load thresholds
45acdf7 hc.conf: CRIT at load 4 per CPU
499a94a (origin/main, origin/HEAD) README: the release process
$ git reset --hard HEAD~1
HEAD is now at 3747ba2 README: document the load thresholds
$ git log --oneline -3
3747ba2 (HEAD -> main) README: document the load thresholds
45acdf7 hc.conf: CRIT at load 4 per CPU
499a94a (origin/main, origin/HEAD) README: the release process
$ git status -sb
## main...origin/main [ahead 2]
```

**Why it works:** `reset --hard` moved `main` back three commits, but the commits stayed in the repository, and the reflog remembered the move. Resetting to `HEAD@{1}` undid the reset itself. Careful: the reflog only saves **commits**. If there had been uncommitted edits, `--hard` would have destroyed them for good.

</details>

### 5 · A deleted branch (L03)
**On Asha's laptop**, `~/rescue/05-deleted-branch`.

> Asha, 10:02: I cleaned up my branches and deleted spike/json-alerts with -D. Turns out Rahul wants that spike. Two commits, never pushed.

Recreate `spike/json-alerts` with both of its commits.

<details>
<summary>Hint</summary>

`git branch -D` deletes a name, not commits. The reflog still lists the commits you made while you were on that branch, and the moment you switched away from it. The newest commit on the branch is the one to point the name at.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/rescue/05-deleted-branch
$ git branch -a
* main
  remotes/origin/HEAD -> origin/main
  remotes/origin/main
  remotes/origin/release/1.2
$ git reflog -6
499a94a (HEAD -> main, origin/main, origin/HEAD) HEAD@{0}: checkout: moving from spike/json-alerts to main
50c5d8e HEAD@{1}: commit: spike: add the host name to JSON alerts
05dc23b HEAD@{2}: commit: spike: format alerts as JSON
499a94a (HEAD -> main, origin/main, origin/HEAD) HEAD@{3}: checkout: moving from main to spike/json-alerts
499a94a (HEAD -> main, origin/main, origin/HEAD) HEAD@{4}: clone: from /srv/git/s05/allcsvideos-ops.git
$ git branch spike/json-alerts 50c5d8e
$ git log --oneline main..spike/json-alerts
50c5d8e (spike/json-alerts) spike: add the host name to JSON alerts
05dc23b spike: format alerts as JSON
$ git show spike/json-alerts:hc/lib/json.sh
# json.sh: format an alert as one line of JSON
alert_json() {   # alert_json STATUS CHECK DETAIL
  printf '{"host":"%s","status":"%s","check":"%s","detail":"%s"}\n' "$(hostname)" "$1" "$2" "$3"
}
```

`main..spike/json-alerts` lists the commits on the spike that `main` doesn't have: exactly the two. `git show branch:path` prints a file from a commit without switching to it.

**Why it works:** the last thing the branch pointed to is the last commit made on it, `HEAD@{1}`, just before the switch back to main. The reflog is local to your clone. If Asha had deleted the folder, the spike would be gone, because it was never pushed: push spikes you might want back, even to a personal branch.

</details>

### 6 · Stash juggling (L03)
**On Asha's laptop**, `~/rescue/06-stash`.

> Rahul, 10:15: Asha, quick one: the README says "helth". Can you push a fix on a new branch, fix/readme-typo, from main? Right now, please.

Asha is in the middle of work on `feature/check-docker`: an edit to `hc.conf` and a **new** test file, nothing committed. Save that work, push the typo fix on `fix/readme-typo` (starting from `origin/main`), then come back and get every bit of the work back. There's also an old stash from last week: check what it holds, then drop it (Rahul decided to keep the 3-second timeout).

<details>
<summary>Hint</summary>

`git stash list` first, so you know what's already there. A plain `git stash` leaves **untracked** files behind, and they'd follow you to the other branch: add `-u`. `-m` gives the stash a name. After a push, your stash is `stash@{0}` and older ones move up by one. `git stash show -p stash@{N}` shows a stash as a diff; `pop` applies and drops one; `drop` just drops it.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/rescue/06-stash
$ git status -s
 M hc/hc.conf
?? hc/tests/docker.conf
$ git stash list
stash@{0}: On main: try HTTP_TIMEOUT=2
$ git stash push -u -m "docker checks WIP"
Saved working directory and index state On feature/check-docker: docker checks WIP
$ git status -s
$ git stash list
stash@{0}: On feature/check-docker: docker checks WIP
stash@{1}: On main: try HTTP_TIMEOUT=2
$ git switch -c fix/readme-typo origin/main
branch 'fix/readme-typo' set up to track 'origin/main'.
Switched to a new branch 'fix/readme-typo'
$ grep -n helth README.md
5:- `hc/`: the server helth check, from the Module 3 build
$ sed -i 's/helth/health/' README.md
$ git commit -am "README: fix a typo"
[fix/readme-typo e4c5b06] README: fix a typo
 1 file changed, 1 insertion(+), 1 deletion(-)
$ git push -u origin fix/readme-typo
…
To /srv/git/s06/allcsvideos-ops.git
 * [new branch]      fix/readme-typo -> fix/readme-typo
branch 'fix/readme-typo' set up to track 'origin/fix/readme-typo'.
$ git switch feature/check-docker
Switched to branch 'feature/check-docker'
$ git stash pop stash@{0}
On branch feature/check-docker
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   hc/hc.conf

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	hc/tests/docker.conf

no changes added to commit (use "git add" and/or "git commit -a")
Dropped stash@{0} (9d4656f9b3bae87a6d302b3f348ee8fc0ea25b4f)
$ git status -s
 M hc/hc.conf
?? hc/tests/docker.conf
$ git stash list
stash@{0}: On main: try HTTP_TIMEOUT=2
$ git stash show -p stash@{0}
diff --git a/hc/hc.conf b/hc/hc.conf
index e91d5bc..068ffba 100644
--- a/hc/hc.conf
+++ b/hc/hc.conf
@@ -10,7 +10,7 @@ LOAD_WARN=2
 LOAD_CRIT=3
 MOUNTS=/ /data /srv
 SERVICES=nginx allcsvideos-api redis
-HTTP_TIMEOUT=3
+HTTP_TIMEOUT=2
 # a real chat webhook URL is a secret: keep this file mode 640
 WEBHOOK_URL=http://hooks:9000/hc
 # TLS certificates: WARN when one expires in this many days or fewer
$ git stash drop stash@{0}
Dropped stash@{0} (fa66035f13990a583c1dd70332cc8437087e9f14)
$ git stash list
```

The hashes of the typo commit and of the stash you made (`e4c5b06`, `9d4656f`) will differ; the old stash, `fa66035`, is the same for everyone. Starting the branch from `origin/main` made it track `origin/main` at first; `push -u` then set its upstream to its own branch on origin.

**Why it works:** a stash is a commit on the side, with your index and working tree in it, and `-u` adds the untracked files. Notice the numbering shift: right after the push, the old stash was `stash@{1}`, and once the pop removed yours, it became `stash@{0}` again. Always read `git stash list` before `pop` or `drop`.

</details>

### 7 · Finish a merge, keep both changes (L03)
**On Asha's laptop**, `~/rescue/07-merge-conflict`.

> Asha, 10:40 (to herself): I merged origin/main into tune/disk-thresholds and got a conflict in hc.conf. I must not lose Priya's change.

Finish the merge that's in progress. The result must keep **both** changes: Priya's new disk warning on `main`, and Asha's new disk critical on her branch. No marker lines may be left, and `hc` must still accept the config.

<details>
<summary>Hint</summary>

`git status` shows the unmerged file. Plain markers show only the two sides. Set `merge.conflictstyle zdiff3` and run `git checkout --merge` on the file to recreate the conflict **with the base**, then compare each side with the base to see who changed what. Resolve in your editor (or take one side and re-apply the other side's one-line change), check that no markers are left, `git add`, then `git commit --no-edit`.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/rescue/07-merge-conflict
$ git status
On branch tune/disk-thresholds
You have unmerged paths.
  (fix conflicts and run "git commit")
  (use "git merge --abort" to abort the merge)

Changes to be committed:
	modified:   README.md

Unmerged paths:
  (use "git add <file>..." to mark resolution)
	both modified:   hc/hc.conf

$ sed -n '/^<<<<<<<.*/,/^>>>>>>>.*/p' hc/hc.conf
<<<<<<< HEAD
DISK_WARN=80
DISK_CRIT=95
=======
DISK_WARN=85
DISK_CRIT=90
>>>>>>> origin/main
$ git config merge.conflictstyle zdiff3
$ git checkout --merge hc/hc.conf
Recreated 1 merge conflict
$ sed -n '/^<<<<<<<.*/,/^>>>>>>>.*/p' hc/hc.conf
<<<<<<< ours
DISK_WARN=80
DISK_CRIT=95
||||||| base
DISK_WARN=80
DISK_CRIT=90
=======
DISK_WARN=85
DISK_CRIT=90
>>>>>>> theirs
```

Now it's clear. Against the base (80 and 90), Asha changed only `DISK_CRIT` (to 95), and `origin/main` changed only `DISK_WARN` (to 85). They don't disagree at all: the answer is `DISK_WARN=85` and `DISK_CRIT=95`. In `nano`, make the block read those two lines and delete the other seven. Or, as here: take main's version of the file, and re-apply Asha's one-line change on top.

```text
$ git checkout --theirs hc/hc.conf
Updated 1 path from the index
$ sed -i 's/^DISK_CRIT=90$/DISK_CRIT=95/' hc/hc.conf
$ grep -n '^DISK' hc/hc.conf
3:DISK_WARN=85
4:DISK_CRIT=95
$ grep -c -E '^(<<<<<<<|\|\|\|\|\|\|\||=======|>>>>>>>)' hc/hc.conf
0
$ hc/bin/hc
hc: config ok
$ git add hc/hc.conf
$ git status -s
M  README.md
M  hc/hc.conf
$ git commit --no-edit
[tune/disk-thresholds 7221ac4] Merge remote-tracking branch 'origin/main' into tune/disk-thresholds
$ git log --oneline --graph -4
*   7221ac4 (HEAD -> tune/disk-thresholds) Merge remote-tracking branch 'origin/main' into tune/disk-thresholds
|\
| * be9ad9f (origin/main, origin/HEAD) README: mention the data volume
| * ca3f91c hc.conf: WARN at 85% disk
* | fa47f9a hc.conf: CRIT at 95% disk
|/
```

The merge commit's hash (`7221ac4`) will differ on yours. `README.md` was already staged: only `main` had changed it, so Git merged it on its own.

**Why it works:** a conflict is a decision, not a side to pick. With plain markers, keeping "HEAD" would have silently thrown away Priya's 85. The base section of zdiff3 shows what each side actually changed, so you can keep both. `git checkout --theirs` alone would have dropped Asha's 95: only the `sed` after it makes it a real resolution.

</details>

### 8 · Get out of a bad rebase (L03)
**On Priya's laptop**, `~/rescue/08-bad-rebase`.

> Priya, 11:05: I ran git pull --rebase origin main on feature/cert-check. Conflict in hc.conf. I edited it for twenty minutes, and now Git says "all conflicts fixed", but the file still has ======= in it and I've lost track of which number is whose. I just want my branch back the way it was this morning.

Stop the rebase and put the branch, the index and the working tree back exactly as they were before it started. Prove that nothing of Priya's was lost.

<details>
<summary>Hint</summary>

`git status` shows the rebase in progress and what's still to do. Look at the conflicted lines before you decide: is it worth continuing? Every rebase can be cancelled with `git rebase --abort`, until it finishes. Afterwards, `git log` and the branch's own reflog (`git reflog -1 <branch>`) show whether the branch moved.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/rescue/08-bad-rebase
$ git status
interactive rebase in progress; onto 0bd957d
Last command done (1 command done):
   pick 3c823a1 checks: add check_cert
Next commands to do (2 remaining commands):
   pick fba7e9c README: document check_cert
   pick 9d018d0 tests: rate 100 is CRIT
  (use "git rebase --edit-todo" to view and edit)
You are currently rebasing branch 'feature/cert-check' on '0bd957d'.
  (all conflicts fixed: run "git rebase --continue")

Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
	modified:   hc/hc.conf
	modified:   hc/lib/checks.sh

$ grep -n -A3 '^CERT_DAYS' hc/hc.conf
17:CERT_DAYS=25
18-=======
19:CERT_DAYS=21
20->>>>>>> 3c823a1 (checks: add check_cert)
$ git rebase --abort
$ git status
On branch feature/cert-check
nothing to commit, working tree clean
$ git log --oneline --graph -4
* 9d018d0 (HEAD -> feature/cert-check) tests: rate 100 is CRIT
* fba7e9c README: document check_cert
* 3c823a1 checks: add check_cert
* 499a94a (main) README: the release process
$ grep -n '^CERT_DAYS' hc/hc.conf
17:CERT_DAYS=21
$ git reflog -1 feature/cert-check
9d018d0 (HEAD -> feature/cert-check) feature/cert-check@{0}: commit: tests: rate 100 is CRIT
```

Look at what Git called "all conflicts fixed": a `25` that neither side wrote (main has 30, Priya 21), a `=======` and a `>>>>>>>` line. Git only knows that the file was `git add`ed. It never checks what's inside. Continuing would have committed that file.

**Why it works:** during a rebase, the branch name isn't moved until the very last commit is replayed. `--abort` throws away the half-done copies and puts `HEAD`, the index and the files back at the original tip, `9d018d0`. The branch's reflog proves it: its last move is still Priya's own commit from this morning. Try again calmly, with zdiff3 on (scenario 7), and remember that during a rebase "ours" is `main` and "theirs" is your own commit.

</details>

### 9 · Squash before the pull request (L03, L04)
**On Priya's laptop**, `~/rescue/09-squash`.

> Priya, 11:30: My CERT_HOSTS change is ready for review, but it's four commits: the change, "wip", "fix typo" and "wip again". Rahul will hate that. How do I make it one commit before I push?

Turn the four commits into **one** commit, `checks: add CERT_HOSTS`, with exactly the same final code. Then push the branch so Priya can open the pull request.

<details>
<summary>Hint</summary>

`git rebase -i HEAD~4` opens the last four commits in the editor, oldest first, each with `pick`. Keep the first `pick`, and change the other three to `fixup`: each one melts into the commit above it, and its message is dropped. After the rebase, `ORIG_HEAD` still points at the old tip: `git diff ORIG_HEAD HEAD` proves the code didn't change.

</details>

<details>
<summary>Answer</summary>

`git rebase -i HEAD~4` opens this to-do list in `nano` (Git's help comments below it are left out here):

```text
pick 5f610e9 checks: add CERT_HOSTS
pick 73f2ee6 wip
pick f9ff627 fix typo
pick 4cfce25 wip again
```

Change lines 2 to 4 from `pick` to `fixup`, save and exit. The same edit without an editor sets `GIT_SEQUENCE_EDITOR` (the editor Git uses for the to-do list) to a `sed` command, for this one run:

```text
$ cd ~/rescue/09-squash
$ git log --oneline origin/main..
4cfce25 (HEAD -> feature/cert-hosts) wip again
f9ff627 fix typo
73f2ee6 wip
5f610e9 checks: add CERT_HOSTS
$ GIT_SEQUENCE_EDITOR="sed -i '2,4s/^pick/fixup/'" git rebase -i HEAD~4
hint: Waiting for your editor to close the file...
Successfully rebased and updated refs/heads/feature/cert-hosts.
$ git log --oneline origin/main..
c6f6ece (HEAD -> feature/cert-hosts) checks: add CERT_HOSTS
$ git diff ORIG_HEAD HEAD --stat
$ git show --stat --format='%h %an %ad%n%s' HEAD
c6f6ece Priya Tue Nov 24 14:00:00 2026 +0530
checks: add CERT_HOSTS

 README.md        | 2 ++
 hc/hc.conf       | 1 +
 hc/lib/checks.sh | 2 +-
 3 files changed, 4 insertions(+), 1 deletion(-)
$ git push -u origin feature/cert-hosts
…
To /srv/git/s09/allcsvideos-ops.git
 * [new branch]      feature/cert-hosts -> feature/cert-hosts
branch 'feature/cert-hosts' set up to track 'origin/feature/cert-hosts'.
```

The squashed commit's hash (`c6f6ece`) will differ on yours. The empty `git diff` is the proof: same code, one commit.

**Why it works:** interactive rebase replays the commits as the list says: `fixup` folds a commit into the one before it and drops its message. It's safe here because the branch had never been pushed. (`git reset --soft origin/main` followed by one `git commit` gets the same result in a different way.)

</details>

### 10 · A bad commit on main, already pushed (L03, L04)
**On Asha's laptop**, `~/rescue/10-pushed-bad-commit`.

> Rahul, 11:52: Asha, hc fails on every server since this morning: unknown setting. It's Priya's rename in hc.conf, and it's on main, and everyone has pulled it. Undo it, now. Don't rewrite main.

Undo the bad commit on `main` in a way that's safe for everyone who already has it, prove `hc` accepts the config again, and push.

<details>
<summary>Hint</summary>

A pushed commit belongs to everyone who pulled it: `reset` plus a force-push would pull the ground from under them. `git revert` makes a **new** commit that applies the exact opposite change. Then a normal `git push`.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/rescue/10-pushed-bad-commit
$ git log --oneline -3
3a5322a (HEAD -> main, origin/main, origin/HEAD) hc.conf: rename HTTP_TIMEOUT to HTTP_TIMEOUT_SECONDS
499a94a README: the release process
046a79a (tag: v1.3.0) hc: version 1.3.0
$ hc/bin/hc; echo "exit $?"
hc: unknown setting HTTP_TIMEOUT_SECONDS
exit 3
$ git status -sb
## main...origin/main
$ git revert --no-edit HEAD
[main 8914a9c] Revert "hc.conf: rename HTTP_TIMEOUT to HTTP_TIMEOUT_SECONDS"
 Date: Tue Oct 20 21:48:13 2026 +0530
 1 file changed, 1 insertion(+), 1 deletion(-)
$ hc/bin/hc; echo "exit $?"
hc: config ok
exit 0
$ git log --oneline -3
8914a9c (HEAD -> main) Revert "hc.conf: rename HTTP_TIMEOUT to HTTP_TIMEOUT_SECONDS"
3a5322a (origin/main, origin/HEAD) hc.conf: rename HTTP_TIMEOUT to HTTP_TIMEOUT_SECONDS
499a94a README: the release process
$ git show --format='%s%n%n%b' --stat HEAD
Revert "hc.conf: rename HTTP_TIMEOUT to HTTP_TIMEOUT_SECONDS"

This reverts commit 3a5322a018bb2302abf7a2ef99e23edf47adceae.


 hc/hc.conf | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
$ git push
…
To /srv/git/s10/allcsvideos-ops.git
   3a5322a..8914a9c  main -> main
$ git status -sb
## main...origin/main
```

The revert's hash and date will differ on yours. Exit code 3 is hc's UNKNOWN, from the Module 3 build.

**Why it works:** revert only **adds** a commit, so the push is a plain fast-forward (`3a5322a..8914a9c`, no `+`, no force). Everyone gets the fix with a normal `git pull`, and history records both the mistake and its undo, with the hash it reverted.

</details>

### 11 · A token in the last commit (L01, L03)
**On Asha's laptop**, `~/rescue/11-secret`.

> Asha, 12:10 (to herself): Wait. My last commit on feature/chat-alerts has the real chat webhook URL in hc.conf, token and all. I was about to push it.

Remove the token from the commit before it's pushed, keep the rest of the commit (the README section), prove that no commit on the branch contains the token, and push the branch.

<details>
<summary>Hint</summary>

`git grep` searches the tracked files. Put the placeholder URL back (the line was `WEBHOOK_URL=http://hooks:9000/hc` before), then `git commit -a --amend --no-edit`: the commit is rebuilt without the token. `git log -p origin/main..HEAD` prints every change on the branch that origin doesn't have yet: `grep -c` it for the token.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/rescue/11-secret
$ git status -sb
## feature/chat-alerts
$ git show --stat --format='%h %s' HEAD
cbae042 notify: send alerts to the team chat

 README.md  | 4 ++++
 hc/hc.conf | 2 +-
 2 files changed, 5 insertions(+), 1 deletion(-)
$ git grep -n token
hc/hc.conf:15:WEBHOOK_URL=https://chat.example.com/hooks/allcs-alerts?token=demo-token-123
$ sed -i 's|^WEBHOOK_URL=.*|WEBHOOK_URL=http://hooks:9000/hc|' hc/hc.conf
$ git diff
diff --git a/hc/hc.conf b/hc/hc.conf
index a47b094..e91d5bc 100644
--- a/hc/hc.conf
+++ b/hc/hc.conf
@@ -12,6 +12,6 @@ MOUNTS=/ /data /srv
 SERVICES=nginx allcsvideos-api redis
 HTTP_TIMEOUT=3
 # a real chat webhook URL is a secret: keep this file mode 640
-WEBHOOK_URL=https://chat.example.com/hooks/allcs-alerts?token=demo-token-123
+WEBHOOK_URL=http://hooks:9000/hc
 # TLS certificates: WARN when one expires in this many days or fewer
 CERT_DAYS=14
$ git commit -a --amend --no-edit
[feature/chat-alerts 9e8e879] notify: send alerts to the team chat
 Date: Wed Nov 25 11:00:00 2026 +0530
 1 file changed, 4 insertions(+)
$ git show --stat --format='%h %s' HEAD
9e8e879 notify: send alerts to the team chat

 README.md | 4 ++++
 1 file changed, 4 insertions(+)
$ git log -p origin/main..HEAD | grep -c demo-token
0
$ git grep -n token
$ hc/bin/hc
hc: config ok
$ git push -u origin feature/chat-alerts
…
To /srv/git/s11/allcsvideos-ops.git
 * [new branch]      feature/chat-alerts -> feature/chat-alerts
branch 'feature/chat-alerts' set up to track 'origin/feature/chat-alerts'.
```

The amended hash (`9e8e879`) will differ on yours. The `git status -sb` line shows no upstream at all: proof the branch had never been pushed. The real URL belongs on the servers only, in `/etc/hc/hc.conf` with mode 640, as the comment above it says.

**Why it works:** amend replaced the commit before anyone else had it, so the token never left the laptop: nothing to rotate. The old commit still sits in Asha's local reflog until it expires, but it's never pushed. Had the token been **pushed**, this wouldn't be enough: everyone who fetched has it. Then you revoke the token and issue a new one first, then rewrite the history and scan for secrets before they land, which is Module 18.

</details>

### 12 · Someone force-pushed my branch (L03)
**On Priya's laptop**, `~/rescue/12-force-push`.

> Priya, 14:05: I ran git pull on feature/notify-v2 and got "fatal: Need to specify how to reconcile divergent branches". I haven't touched anything since! And I have one commit that isn't pushed yet.

Find out what happened, then put Priya's unpushed commit on top of the branch as it is on origin now, without duplicating anyone's commits, and push it.

<details>
<summary>Hint</summary>

Read the fetch lines of the failed pull: a `+` and `(forced update)` mean someone rewrote the branch. `git log --oneline --graph --all` shows the old copies and the new ones side by side. `git pull --rebase` replays only **your** commits onto the new branch, and skips the old copies origin used to have.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/rescue/12-force-push
$ git status -sb
## feature/notify-v2...origin/feature/notify-v2 [ahead 1]
$ git pull
…
From /srv/git/s12/allcsvideos-ops
 + 1930e29...55b924a feature/notify-v2 -> origin/feature/notify-v2  (forced update)
   499a94a..baa118a  main              -> origin/main
hint: You have divergent branches and need to specify how to reconcile them.
hint: You can do so by running one of the following commands sometime before
hint: your next pull:
hint:
hint:   git config pull.rebase false  # merge
hint:   git config pull.rebase true   # rebase
hint:   git config pull.ff only       # fast-forward only
hint:
hint: You can replace "git config" with "git config --global" to set a default
hint: preference for all repositories. You can also pass --rebase, --no-rebase,
hint: or --ff-only on the command line to override the configured default per
hint: invocation.
fatal: Need to specify how to reconcile divergent branches.
$ git status -sb
## feature/notify-v2...origin/feature/notify-v2 [ahead 4, behind 4]
$ git log --oneline --graph --all -9
* 55b924a (origin/feature/notify-v2) README: document NOTIFY_V2
* 78de41e notify: pick the webhook by severity
* bd643b7 notify: NOTIFY_V2 setting, off by default
* baa118a (origin/main, origin/HEAD) hc.conf: MEM_CRIT 5
| * 2ce9cea (HEAD -> feature/notify-v2) notify: log which webhook is used
| * 1930e29 README: document NOTIFY_V2
| * 9322a2f notify: pick the webhook by severity
| * f840376 notify: NOTIFY_V2 setting, off by default
|/
* 499a94a (main) README: the release process
$ git pull --rebase
Successfully rebased and updated refs/heads/feature/notify-v2.
$ git log --oneline --graph -6
* 1f5a1ed (HEAD -> feature/notify-v2) notify: log which webhook is used
* 55b924a (origin/feature/notify-v2) README: document NOTIFY_V2
* 78de41e notify: pick the webhook by severity
* bd643b7 notify: NOTIFY_V2 setting, off by default
* baa118a (origin/main, origin/HEAD) hc.conf: MEM_CRIT 5
* 499a94a (main) README: the release process
$ git push
…
To /srv/git/s12/allcsvideos-ops.git
   55b924a..1f5a1ed  feature/notify-v2 -> feature/notify-v2
```

The graph tells the story: Asha rebased the shared branch onto Rahul's new `main` commit and force-pushed it, so the same three commits now exist twice, under old and new hashes. Priya's rebased commit (`1f5a1ed`) will have a different hash on yours.

**Why it works:** a plain merge here would have put both copies of the three commits into history. `pull --rebase` replays only the commit that origin's branch never had, `notify: log which webhook is used`, onto the new branch, and the push is a normal fast-forward. The lesson for Asha: never rebase a branch others have, and if you must force-push, use `--force-with-lease`.

</details>

### 13 · Every file looks modified (L01)
**On Priya's laptop**, `~/rescue/13-line-endings`.

> Priya, 14:40: Since my last pull, git status says hc/lib/checks.sh and hc/tests/run.sh are modified. I never touched them, and git restore does nothing. And hc doesn't even start any more: something about bash\r?

Find the cause, then fix it for the whole team: every hc script, `hc/bin/hc` included, must be stored with LF line endings, Priya's working copy must be clean, `hc` must run, and the fix must be pushed.

<details>
<summary>Hint</summary>

`\r` is the carriage return of Windows CRLF line endings. `git log` shows the last two commits; `git ls-files --eol` shows the line endings in the index (`i/`), in the working tree (`w/`) and the attribute that applies (`attr/`). An attribute only changes what Git does the **next** time a file is added: `git add --renormalize .` re-adds every file under the current rules. Does the `.gitattributes` pattern even match `hc/bin/hc`?

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/rescue/13-line-endings
$ git status -s
 M hc/lib/checks.sh
 M hc/tests/run.sh
$ git restore hc
$ git status -s
 M hc/lib/checks.sh
 M hc/tests/run.sh
$ hc/bin/hc --version
/usr/bin/env: 'bash\r': No such file or directory
/usr/bin/env: use -[v]S to pass options in shebang lines
$ git log --oneline -3
35880f1 (HEAD -> main, origin/main, origin/HEAD) Add .gitattributes: shell scripts use LF
dcd76f6 hc: tidy up the scripts
499a94a README: the release process
$ git ls-files --eol hc .gitattributes
i/lf    w/lf    attr/                 	.gitattributes
i/crlf  w/crlf  attr/                 	hc/bin/hc
i/lf    w/lf    attr/                 	hc/hc.conf
i/crlf  w/crlf  attr/text eol=lf      	hc/lib/checks.sh
i/crlf  w/crlf  attr/text eol=lf      	hc/tests/run.sh
$ git diff --stat
warning: in the working copy of 'hc/lib/checks.sh', CRLF will be replaced by LF the next time Git touches it
warning: in the working copy of 'hc/tests/run.sh', CRLF will be replaced by LF the next time Git touches it
 hc/lib/checks.sh | 40 ++++++++++++++++++++--------------------
 hc/tests/run.sh  | 34 +++++++++++++++++-----------------
 2 files changed, 37 insertions(+), 37 deletions(-)
$ cat .gitattributes
# shell scripts always use LF line endings
*.sh text eol=lf
```

The diagnosis: Rahul's "tidy up" commit came from a Windows editor and stored three scripts with CRLF (`i/crlf`). Asha then added a `.gitattributes` saying `*.sh` files are LF, but never re-added the files. So for the two `.sh` files, the index holds CRLF while the rule says LF: Git reports them as modified, and `git restore` just writes the same CRLF copy back. `hc/bin/hc` has no `.sh` extension, so the rule doesn't cover it (`attr/` is empty): it looks clean, and it's the file that breaks. Fix the rule, renormalize, commit, then refresh the working copies:

```text
$ echo 'hc/bin/* text eol=lf' >> .gitattributes
$ git add .gitattributes
$ git add --renormalize .
$ git status -s
M  .gitattributes
M  hc/bin/hc
M  hc/lib/checks.sh
M  hc/tests/run.sh
$ git ls-files --eol hc
i/lf    w/crlf  attr/text eol=lf      	hc/bin/hc
i/lf    w/lf    attr/                 	hc/hc.conf
i/lf    w/crlf  attr/text eol=lf      	hc/lib/checks.sh
i/lf    w/crlf  attr/text eol=lf      	hc/tests/run.sh
$ git commit -m "Normalize line endings to LF, hc/bin included"
[main 63f3d17] Normalize line endings to LF, hc/bin included
 4 files changed, 51 insertions(+), 50 deletions(-)
$ rm hc/bin/hc hc/lib/checks.sh hc/tests/run.sh
$ git restore hc
$ git ls-files --eol hc
i/lf    w/lf    attr/text eol=lf      	hc/bin/hc
i/lf    w/lf    attr/                 	hc/hc.conf
i/lf    w/lf    attr/text eol=lf      	hc/lib/checks.sh
i/lf    w/lf    attr/text eol=lf      	hc/tests/run.sh
$ git status -s
$ hc/bin/hc --version
hc 1.3.0
$ git push
…
To /srv/git/s13/allcsvideos-ops.git
   35880f1..63f3d17  main -> main
```

The normalize commit's hash (`63f3d17`) will differ on yours. After the commit the index is LF but the working files are still CRLF (`w/crlf`), so the three scripts are deleted and restored fresh from the index. That's safe here because `git status` was clean after the commit.

One more step for the team. Anyone who pulled the broken commits sees the same phantom changes, and they block a normal pull. They have no real work in those files, so a fetch and a reset to origin is safe for them (run here in a teammate's clone of the broken state; `63f3d17` is the normalize commit from above, so yours will differ):

```text
$ git status -s
 M hc/lib/checks.sh
 M hc/tests/run.sh
$ git pull
Updating 35880f1..63f3d17
error: Your local changes to the following files would be overwritten by merge:
	hc/lib/checks.sh
	hc/tests/run.sh
Please commit your changes or stash them before you merge.
Aborting
$ git fetch
$ git reset --hard origin/main
HEAD is now at 63f3d17 Normalize line endings to LF, hc/bin included
$ git status -s
$ hc/bin/hc --version
hc 1.3.0
```

**Why it works:** `.gitattributes` travels with the repository, so the rule now holds for everyone, whatever their own `core.autocrlf` setting. But a rule only affects files Git adds after it exists: `--renormalize` re-adds the existing ones, and a fresh checkout writes them out with LF.

</details>

### 14 · Ship one fix to the 1.2 servers (L02, L03, L04)
**On Asha's laptop**, `~/rescue/14-hotfix`.

> Rahul, 15:10: Some servers still run hc 1.2 and can't move to 1.3 yet. Their hc.conf has indented comments, and 1.2 rejects them as unknown settings. My fix, "checks: allow indented comments in hc.conf", is on main. Ship that fix, and nothing else, to the 1.2 servers. What's the version number?

Put **only** Rahul's fix on `release/1.2`, with a record of where it came from. Bump the version, tag the release with an annotated tag, and push the branch and the tag. Decide the version number with semver, and explain why.

<details>
<summary>Hint</summary>

`git log --oneline v1.2.0..main` lists everything main has that 1.2.0 doesn't: only one of those commits is the fix. `git cherry-pick -x <hash>` copies one commit onto the current branch and records "cherry picked from commit …". The version lives in `hc/bin/hc`. Semver: MAJOR.MINOR.PATCH, and a backward-compatible bug fix bumps PATCH. Push a branch and a tag in one command: `git push origin <branch> <tag>`.

</details>

<details>
<summary>Answer</summary>

**The version is 1.2.1**: a backward-compatible bug fix bumps PATCH. Not 1.3.0: MINOR is for new functionality (like the new `CERT_DAYS` setting), and a release branch gets fixes only. Not 2.0.0: nothing incompatible changes, and every existing `hc.conf` keeps working.

```text
$ cd ~/rescue/14-hotfix
$ git log --oneline v1.2.0..main
499a94a (HEAD -> main, origin/main, origin/HEAD) README: the release process
046a79a (tag: v1.3.0) hc: version 1.3.0
b1026bb checks: allow indented comments in hc.conf
a98fe6d hc.conf: check /srv too
c6814ba README: document CERT_DAYS
d8378e2 checks: tidy rate()
18dbcc1 tests: rate 0 is OK
6a94878 checks: add the CERT_DAYS setting
b874630 hc.conf: warn at load 2 per CPU
aa32c98 README: how to run the tests
$ git switch release/1.2
branch 'release/1.2' set up to track 'origin/release/1.2'.
Switched to a new branch 'release/1.2'
$ printf 'DISK_WARN=80\n  # an indented comment\n' > /tmp/indented.conf
$ hc/bin/hc -c /tmp/indented.conf; echo "exit $?"
hc: unknown setting   # an indented comment
exit 3
$ git cherry-pick -x b1026bb
Auto-merging hc/lib/checks.sh
[release/1.2 88205b3] checks: allow indented comments in hc.conf
 Author: Rahul <rahul@example.com>
 Date: Mon Nov 16 10:45:00 2026 +0530
 1 file changed, 1 insertion(+), 1 deletion(-)
$ sed -i 's/^readonly VERSION=1.2.0/readonly VERSION=1.2.1/' hc/bin/hc
$ git commit -am "hc: version 1.2.1"
[release/1.2 8f1d3f8] hc: version 1.2.1
 1 file changed, 1 insertion(+), 1 deletion(-)
$ hc/bin/hc -c /tmp/indented.conf; echo "exit $?"
hc: config ok
exit 0
$ hc/bin/hc --version
hc 1.2.1
$ git log --format='%h %s%n%b' -2 | grep -v '^$'
8f1d3f8 hc: version 1.2.1
88205b3 checks: allow indented comments in hc.conf
(cherry picked from commit b1026bb594d404413a0f26cf2541f317a0014e0e)
$ git tag -a v1.2.1 -m "hc 1.2.1"
$ git describe
v1.2.1
$ git log --oneline -4
8f1d3f8 (HEAD -> release/1.2, tag: v1.2.1) hc: version 1.2.1
88205b3 checks: allow indented comments in hc.conf
9b9919e (tag: v1.2.0, origin/release/1.2) hc: version 1.2.0
79970f9 hc.conf: also check redis
$ git push origin release/1.2 v1.2.1
…
To /srv/git/s14/allcsvideos-ops.git
   9b9919e..8f1d3f8  release/1.2 -> release/1.2
 * [new tag]         v1.2.1 -> v1.2.1
```

The two new commit hashes (`88205b3`, `8f1d3f8`) will differ on yours; the "cherry picked from" hash is the same for everyone. The `/tmp/indented.conf` test proves the bug on 1.2.0 and the fix on 1.2.1.

**Why it works:** cherry-pick copies one change, with Rahul as the author and his date, onto a different parent, so it gets a new hash, and `-x` links it back to the original. Merging `main` into `release/1.2` would have shipped the new setting, the version 1.3.0 bump and the unfinished `rate()` change too. The fix was made on main first, then picked down, so it can't go missing from the next release.

</details>

### 15 · Which commit broke the tests? (L03)
**On Asha's laptop**, `~/rescue/15-bisect`.

> Rahul, 16:00: The hc tests fail on main: rate 90 should be CRIT, but it says WARN. v1.2.0 passed. There are ten commits in between. Which one broke it?

Find the first bad commit with a binary search that runs the tests by itself, show what it changed, and leave the repository back on `main`. How should the team undo it?

<details>
<summary>Hint</summary>

`git bisect start`, `git bisect bad` (the current commit), `git bisect good v1.2.0`. Then `git bisect run hc/tests/run.sh`: Git checks out the middle commit, runs the script, and uses its exit code (0 means good, 1 to 127 except 125 means bad). `git bisect reset` returns to where you started.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/rescue/15-bisect
$ hc/tests/run.sh; echo "exit $?"
FAIL  rate 90 is CRIT: expected CRIT, got WARN
5 passed, 1 failed
exit 1
$ git bisect start
status: waiting for both good and bad commits
$ git bisect bad
status: waiting for good commit(s), bad commit known
$ git bisect good v1.2.0
Bisecting: 4 revisions left to test after this (roughly 2 steps)
[d8378e298ae647d512aec64992b51e7b32e44a72] checks: tidy rate()
$ git bisect run hc/tests/run.sh
running 'hc/tests/run.sh'
FAIL  rate 90 is CRIT: expected CRIT, got WARN
5 passed, 1 failed
Bisecting: 2 revisions left to test after this (roughly 1 step)
[b8746303afc9d6f052e045f48f0acb439f862935] hc.conf: warn at load 2 per CPU
running 'hc/tests/run.sh'
5 passed, 0 failed
Bisecting: 0 revisions left to test after this (roughly 1 step)
[18dbcc19c4df22a6ce3e04ed5c90b07c0bd34020] tests: rate 0 is OK
running 'hc/tests/run.sh'
6 passed, 0 failed
d8378e298ae647d512aec64992b51e7b32e44a72 is the first bad commit
commit d8378e298ae647d512aec64992b51e7b32e44a72
Author: Rahul <rahul@example.com>
Date:   Wed Nov 11 17:05:00 2026 +0530

    checks: tidy rate()

 hc/lib/checks.sh | 5 +++--
 1 file changed, 3 insertions(+), 2 deletions(-)
bisect found first bad commit
$ git show d8378e2 -- hc/lib/checks.sh
commit d8378e298ae647d512aec64992b51e7b32e44a72
Author: Rahul <rahul@example.com>
Date:   Wed Nov 11 17:05:00 2026 +0530

    checks: tidy rate()

diff --git a/hc/lib/checks.sh b/hc/lib/checks.sh
index 655c8c9..4c0647f 100644
--- a/hc/lib/checks.sh
+++ b/hc/lib/checks.sh
@@ -13,7 +13,8 @@ load_config() {   # load_config FILE: read KEY=value lines, refuse unknown setti
 }

 rate() {   # rate VALUE WARN CRIT: prints OK, WARN or CRIT
-  if (( $1 >= $3 )); then echo CRIT
-  elif (( $1 >= $2 )); then echo WARN
+  local v=$1 warn=$2 crit=$3
+  if (( v > crit )); then echo CRIT
+  elif (( v >= warn )); then echo WARN
   else echo OK; fi
 }
$ git bisect reset
Previous HEAD position was 18dbcc1 tests: rate 0 is OK
Switched to branch 'main'
Your branch is up to date with 'origin/main'.
```

The culprit is `d8378e2`, "checks: tidy rate()": while renaming the variables, `>=` became `>` in the CRIT line, so a value exactly at the threshold, 90, is no longer CRIT. Three test runs instead of ten. Every hash here is the same on your machine.

**How to undo it:** the commit is on `main`, pushed, and even part of the `v1.3.0` release. So not `reset`: `git revert d8378e2`, the same as scenario 10. Scenario 18 does exactly that, and ships the fix.

**Why it works:** bisect is a binary search over history. Each test halves the range, so ten commits need about three runs, and a thousand would need about ten. `bisect run` only needs a command whose exit code means good or bad, which is exactly what a test script is.

</details>

---

## Final challenge

Three rescues that each need several of the tools above. Each one has its own folder, like the others.

### 16 · Lost after a force-push (L01, L03)
**On Priya's laptop**, `~/rescue/16-lost-after-force-push`.

> Priya, 16:30: Same thing as this afternoon, but on feature/alert-routing: Asha force-pushed it, my pull failed, and this time I "fixed" it with git reset --hard origin/feature/alert-routing, like a forum said. My two commits from this morning are gone. They were never pushed.

Get both of Priya's commits back, on top of the branch as it is on origin now, with no duplicated commits, and push them, without any force.

<details>
<summary>Hint</summary>

Two rescues in a row. First, the reflog shows where `HEAD` was just before the reset: go back there. Now you're in exactly the situation of scenario 12, so the same command finishes the job.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/rescue/16-lost-after-force-push
$ git status -sb
## feature/alert-routing...origin/feature/alert-routing
$ git log --oneline -4
c4a2553 (HEAD -> feature/alert-routing, origin/feature/alert-routing) README: document ROUTE_CRIT
ba8a1cf notify: ROUTE_CRIT setting
baa118a (origin/main, origin/HEAD) hc.conf: MEM_CRIT 5
499a94a (main) README: the release process
$ git reflog -5
c4a2553 (HEAD -> feature/alert-routing, origin/feature/alert-routing) HEAD@{0}: reset: moving to origin/feature/alert-routing
562070e HEAD@{1}: commit: tests: WARN alerts go to chat
572fb0e HEAD@{2}: commit: notify: route CRIT alerts to the pager
ab32bf1 HEAD@{3}: pull: Fast-forward
b73a62e HEAD@{4}: commit: notify: ROUTE_CRIT setting
$ git reset --hard HEAD@{1}
HEAD is now at 562070e tests: WARN alerts go to chat
$ git log --oneline --graph --all -8
* c4a2553 (origin/feature/alert-routing) README: document ROUTE_CRIT
* ba8a1cf notify: ROUTE_CRIT setting
* baa118a (origin/main, origin/HEAD) hc.conf: MEM_CRIT 5
| * 562070e (HEAD -> feature/alert-routing) tests: WARN alerts go to chat
| * 572fb0e notify: route CRIT alerts to the pager
| * ab32bf1 README: document ROUTE_CRIT
| * b73a62e notify: ROUTE_CRIT setting
|/
* 499a94a (main) README: the release process
$ git pull --rebase
Successfully rebased and updated refs/heads/feature/alert-routing.
$ git log --oneline --graph -6
* 361d80b (HEAD -> feature/alert-routing) tests: WARN alerts go to chat
* 9ac5f13 notify: route CRIT alerts to the pager
* c4a2553 (origin/feature/alert-routing) README: document ROUTE_CRIT
* ba8a1cf notify: ROUTE_CRIT setting
* baa118a (origin/main, origin/HEAD) hc.conf: MEM_CRIT 5
* 499a94a (main) README: the release process
$ hc/bin/hc
hc: config ok
$ grep -n -A3 '^route()' hc/lib/checks.sh
22:route() {   # route SEVERITY: where an alert of that severity goes
23-  if [[ $1 == CRIT ]]; then echo "${ROUTE_CRIT:-chat}"; else echo chat; fi
24-}
$ git push
…
To /srv/git/s16/allcsvideos-ops.git
   c4a2553..361d80b  feature/alert-routing -> feature/alert-routing
```

The two rebased hashes (`9ac5f13`, `361d80b`) will differ on yours.

**Why it works:** the forum's `reset --hard` only moved the branch name; Priya's commits were still in the repository, and the reflog still knew them. Going back to `HEAD@{1}` recreated the situation of scenario 12, where `pull --rebase` replays only the two commits origin never had, and skips the old copies of `notify: ROUTE_CRIT setting` and `README: document ROUTE_CRIT`.

</details>

### 17 · Ready for review (L01, L03, L04)
**On Asha's laptop**, `~/rescue/17-ready-for-review`.

> Asha, 17:00 (to herself): feature/team-webhook is done. Before I push and open the pull request: the middle commit has the team channel's real webhook token in it, and the last commit is called "wip". Neither may reach the server.

Clean the branch up before its first push: no commit on the branch may contain the token, the `wip` commit's README line must be folded into the commit before it, and the first commit must stay as it is. Push the result.

<details>
<summary>Hint</summary>

The token isn't in the **last** commit, so amend can't reach it. Fix the file, then commit with `git commit -a --fixup=<hash of the middle commit>`. `git rebase -i --autosquash origin/main` then moves that fixup under its target and marks it `fixup` for you. In the same to-do list, change `wip` to `fixup` too.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/rescue/17-ready-for-review
$ git log --oneline origin/main..
f18b8ac (HEAD -> feature/team-webhook) wip
417d186 hc.conf: send WARN alerts to the team channel
7b01048 checks: add WEBHOOK_TEAM to the known settings
$ git log -p origin/main.. | grep -n demo-token
33:+WEBHOOK_TEAM=https://chat.example.com/hooks/allcs-team?token=demo-token-456
$ sed -i 's|^WEBHOOK_TEAM=.*|WEBHOOK_TEAM=http://hooks:9000/hc-team|' hc/hc.conf
$ git commit -a --fixup=417d186
[feature/team-webhook 7ce3e27] fixup! hc.conf: send WARN alerts to the team channel
 1 file changed, 1 insertion(+), 1 deletion(-)
$ git log --oneline origin/main..
7ce3e27 (HEAD -> feature/team-webhook) fixup! hc.conf: send WARN alerts to the team channel
f18b8ac wip
417d186 hc.conf: send WARN alerts to the team channel
7b01048 checks: add WEBHOOK_TEAM to the known settings
```

`git rebase -i --autosquash origin/main` opens this to-do list (help comments left out). Autosquash has already moved the fixup under its target:

```text
pick 7b01048 checks: add WEBHOOK_TEAM to the known settings
pick 417d186 hc.conf: send WARN alerts to the team channel
fixup 7ce3e27 fixup! hc.conf: send WARN alerts to the team channel
pick f18b8ac wip
```

Change the last line's `pick` to `fixup`, save and exit. Without an editor:

```text
$ GIT_SEQUENCE_EDITOR="sed -i 's/^pick \(.*\) wip$/fixup \1 wip/'" git rebase -i --autosquash origin/main
hint: Waiting for your editor to close the file...
Successfully rebased and updated refs/heads/feature/team-webhook.
$ git log --oneline origin/main..
96a4078 (HEAD -> feature/team-webhook) hc.conf: send WARN alerts to the team channel
7b01048 checks: add WEBHOOK_TEAM to the known settings
$ git log -p origin/main.. | grep -c demo-token
0
$ git show --format='%h %s' HEAD
96a4078 hc.conf: send WARN alerts to the team channel

diff --git a/README.md b/README.md
index 32afd5b..6ce969a 100644
--- a/README.md
+++ b/README.md
@@ -15,3 +15,5 @@ Run `hc/tests/run.sh` before every push. It exits 0 only when every test passes.
 ## Releases

 Releases are tagged `vMAJOR.MINOR.PATCH` (semver). Fixes for a shipped version go to its `release/X.Y` branch.
+
+`WEBHOOK_TEAM`: WARN alerts go to the team channel; CRIT alerts page the on-call person.
diff --git a/hc/hc.conf b/hc/hc.conf
index e91d5bc..cc9a3b7 100644
--- a/hc/hc.conf
+++ b/hc/hc.conf
@@ -15,3 +15,5 @@ HTTP_TIMEOUT=3
 WEBHOOK_URL=http://hooks:9000/hc
 # TLS certificates: WARN when one expires in this many days or fewer
 CERT_DAYS=14
+# WARN alerts go to the team channel
+WEBHOOK_TEAM=http://hooks:9000/hc-team
$ hc/bin/hc
hc: config ok
$ git push -u origin feature/team-webhook
…
To /srv/git/s17/allcsvideos-ops.git
 * [new branch]      feature/team-webhook -> feature/team-webhook
branch 'feature/team-webhook' set up to track 'origin/feature/team-webhook'.
```

The fixup and the rewritten commit (`7ce3e27`, `96a4078`) will have different hashes on yours. The first commit keeps its hash, `7b01048`: nothing under it changed, so the rebase reused it.

**Why it works:** `--fixup` records which commit a change belongs to, and autosquash turns that into the right to-do list. The token never reached the server, so rewriting was safe and nothing needs rotating. Two commits that each do one thing make a pull request that's easy to review (lesson 4).

</details>

### 18 · Ship 1.3.1 (L02, L03, L04)
**On Asha's laptop**, `~/rescue/18-ship-1.3.1`.

> Rahul, 17:30: The rate() bug from scenario 15 is in v1.3.0, and that's on most servers. Fix main, and ship a 1.3.1 with only the fix. There's no release/1.3 branch yet.

Undo the bad commit on `main` safely and push it. Then create `release/1.3` from the `v1.3.0` tag, bring **only** the fix to it with a record of where it came from, bump the version, prove the tests pass, tag `v1.3.1` and push the branch and the tag.

<details>
<summary>Hint</summary>

Scenario 15 found the commit: `d8378e2`. `git tag --contains` shows which releases have it. Pushed, so `git revert`. A release branch can start at a tag: `git switch -c release/1.3 v1.3.0`. The fix to pick down is the revert commit itself, the tip of `main`. Same version and tag steps as scenario 14.

</details>

<details>
<summary>Answer</summary>

```text
$ cd ~/rescue/18-ship-1.3.1
$ git tag --contains d8378e2
v1.3.0
$ git revert --no-edit d8378e2
Auto-merging hc/lib/checks.sh
[main 8ce949b] Revert "checks: tidy rate()"
 Date: Tue Oct 20 21:48:14 2026 +0530
 1 file changed, 2 insertions(+), 3 deletions(-)
$ hc/tests/run.sh
6 passed, 0 failed
$ git push
…
To /srv/git/s18/allcsvideos-ops.git
   499a94a..8ce949b  main -> main
$ git switch -c release/1.3 v1.3.0
Switched to a new branch 'release/1.3'
$ git cherry-pick -x main
[release/1.3 2fa193c] Revert "checks: tidy rate()"
 Date: Tue Oct 20 21:48:14 2026 +0530
 1 file changed, 2 insertions(+), 3 deletions(-)
$ sed -i 's/^readonly VERSION=1.3.0/readonly VERSION=1.3.1/' hc/bin/hc
$ git commit -am "hc: version 1.3.1"
[release/1.3 09ca0a2] hc: version 1.3.1
 1 file changed, 1 insertion(+), 1 deletion(-)
$ hc/tests/run.sh
6 passed, 0 failed
$ hc/bin/hc --version
hc 1.3.1
$ git tag -a v1.3.1 -m "hc 1.3.1"
$ git log --oneline --graph --all -6
* 8ce949b (origin/main, origin/HEAD, main) Revert "checks: tidy rate()"
* 499a94a README: the release process
| * 09ca0a2 (HEAD -> release/1.3, tag: v1.3.1) hc: version 1.3.1
| * 2fa193c Revert "checks: tidy rate()"
|/
* 046a79a (tag: v1.3.0) hc: version 1.3.0
* b1026bb checks: allow indented comments in hc.conf
$ git push -u origin release/1.3 v1.3.1
…
To /srv/git/s18/allcsvideos-ops.git
 * [new branch]      release/1.3 -> release/1.3
 * [new tag]         v1.3.1 -> v1.3.1
branch 'release/1.3' set up to track 'origin/release/1.3'.
$ git log --format='%h %s%n%b' -2 | grep -v '^$'
09ca0a2 hc: version 1.3.1
2fa193c Revert "checks: tidy rate()"
This reverts commit d8378e298ae647d512aec64992b51e7b32e44a72.
(cherry picked from commit 8ce949b4c2961b45b86be0bc7cdfc955051a9125)
```

All the new hashes and dates (the revert, its copy, the version bump) will differ on yours. The release commit's message now traces the whole chain: the original bug, the revert on main, and the copy on the release branch.

**Why it works:** the fix landed on `main` first, as a revert, because the bug was already shared. Then exactly that one commit was picked onto a release branch cut at the shipped tag, so 1.3.1 is 1.3.0 plus one fix: a PATCH. `main` doesn't get the 1.3.1 version bump. It will become 1.4.0, or 2.0.0, when its next release is cut.

</details>

---

## Clean up

When you're done, remove everything this lab created. The pulled base image, `ubuntu:24.04`, can stay.

```bash
docker rm -f m05lab-lab
docker rmi m05lab-lab
```

These should all print nothing (the lab never creates networks or volumes, so the last two are just a habit worth keeping):

```bash
docker ps -a --filter name=m05lab
docker images --filter reference='m05lab*' -q
docker network ls --filter name=m05lab -q
docker volume ls --filter name=m05lab -q
```

**Score yourself:** 13 to 15 of the rescues solved on your own, plus at least one from the final challenge, means you're ready for Module 06. Under 10, rewatch the lessons named in the titles of the scenarios you missed. Notice the pattern behind every answer: before you fix anything, ask **"has it been pushed?"** Not pushed: amend, reset, rebase. Pushed: revert. Lost: the reflog. That one question decides almost every Git rescue.
