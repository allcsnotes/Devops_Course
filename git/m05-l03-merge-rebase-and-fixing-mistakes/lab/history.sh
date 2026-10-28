#!/bin/bash
# history.sh (runs as root inside the git-team lab container): builds three weeks of team history in allcsvideos-ops FOR THE DEMO.
# Every commit is made by the real user (asha, priya, rahul) in their own clone and pushed to the bare origin;
# the dates are set deliberately with GIT_AUTHOR_DATE / GIT_COMMITTER_DATE (October 21 to November 13, 2026, IST).
# Priya works on feature/notify-rewrite for three weeks without integrating; Asha and Rahul keep committing to main.
set -euo pipefail
O=/srv/git/allcsvideos-ops.git
T=/opt/hc-toolkit
R(){ echo /home/$1/allcsvideos-ops; }
sh_as(){ local u=$1; shift; runuser -l "$u" -c "cd ~/allcsvideos-ops && $*"; }
commit(){ # commit USER 'YYYY-MM-DD HH:MM' 'message' : stage everything in that clone and commit with that date
  local u=$1 d="$2 +0530" m=$3
  chown -R "$u:$u" "$(R "$u")"
  runuser -l "$u" -c "cd ~/allcsvideos-ops && git add -A && GIT_AUTHOR_DATE='$d' GIT_COMMITTER_DATE='$d' git commit -q -m '$m'"; }
sync(){ sh_as "$1" "git pull -q --rebase origin main"; }   # main users always start from the latest main
push(){ sh_as "$1" "git push -q origin ${2:-main}"; }
pe(){ local f=$1; shift; perl -0pi -e "$@" "$f"; }        # in-place edit as root (chown happens in commit)

# ---- origin: a bare repository standing in for GitHub; Asha pushes the M05-L01 repository to it
git init -q --bare --shared=group -b main $O && chgrp -R dev $O
git config --system --add safe.directory $O   # lab plumbing: origin is owned by root, shared with group dev
sh_as asha "git remote add origin $O && git push -q origin main && git push -q origin v0.1 v0.2"
for u in priya rahul; do runuser -l $u -c "git clone -q $O allcsvideos-ops"; done

# ---- Oct 21: Asha imports the rest of the hc toolkit (M03-B01)
A=$(R asha)
mkdir -p $A/hc/bin $A/hc/lib $A/hc/systemd $A/hc/tests
cp $T/bin/hc $A/hc/bin/; cp $T/lib/* $A/hc/lib/; cp $T/systemd/hc.service $T/systemd/hc.timer $A/hc/systemd/
cp $T/tests/* $A/hc/tests/; cp $T/install.sh $A/hc/
commit asha '2026-10-21 10:12' 'hc: import bin, lib, tests and systemd units from the toolkit'; push asha

# ---- Oct 22: Rahul starts a spike and abandons it (left on origin)
sync rahul; sh_as rahul "git switch -q -c spike/prometheus-exporter"
printf '#!/usr/bin/env bash\n# prom.sh: WIP - write hc results as Prometheus textfile metrics\n' > $(R rahul)/hc/lib/prom.sh
commit rahul '2026-10-22 18:05' 'spike: Prometheus textfile exporter (WIP)'; push rahul spike/prometheus-exporter
sh_as rahul "git switch -q main"

# ---- Oct 23 (Friday): Rahul on main, then Priya starts her branch
sync rahul; pe $(R rahul)/hc/hc.conf 's/^SERVICES=.*/SERVICES=nginx allcsvideos-api course-copilot redis/m'
commit rahul '2026-10-23 11:05' 'hc.conf: also check redis'; push rahul

P=$(R priya)
sync priya; sh_as priya "git switch -q -c feature/notify-rewrite"
pe $P/hc/hc.conf 's|^# a real chat webhook URL is a secret.*\nWEBHOOK_URL=.*$|# real chat webhook URLs are secrets: keep this file mode 640\nWEBHOOK_WARN=http://hooks:9000/hc-warn\nWEBHOOK_CRIT=http://hooks:9000/hc-crit|m'
pe $P/hc/lib/checks.sh 's/^      WEBHOOK_URL\)$/      WEBHOOK_WARN WEBHOOK_CRIT)/m'
for f in ok warn unknown; do pe $P/hc/tests/$f.conf 's|^WEBHOOK_URL=(.*)$|WEBHOOK_WARN=$1\nWEBHOOK_CRIT=$1|m'; done
commit priya '2026-10-23 16:20' 'notify: separate webhooks for WARN and CRIT'

# ---- week 1
sync asha
pe $A/hc/bin/hc 's/^  --json         print the results as JSON\n/  --json         print the results as JSON\n  -q, --quiet    print nothing, only set the exit code\n/m'
pe $A/hc/bin/hc 's/^json=0\n/json=0\nquiet=0\n/m; s/^    --json\) json=1 ;;\n/    --json) json=1 ;;\n    -q|--quiet) quiet=1 ;;\n/m; s/^if \(\( json \)\); then\n/if (( quiet )); then\n  :\nelif (( json )); then\n/m'
commit asha '2026-10-26 10:30' 'hc: add a --quiet flag'; push asha

pe $P/hc/bin/hc 's/^  python3 "\$lib\/report.py" alert "\$WEBHOOK_URL" "\$1" "\$2" <<< "\$results"\n/  local url=\$WEBHOOK_WARN\n  [[ \$2 == CRIT ]] && url=\$WEBHOOK_CRIT\n  python3 "\$lib\/report.py" alert "\$url" "\$1" "\$2" <<< "\$results"\n/m'
commit priya '2026-10-26 16:00' 'notify: pick the webhook by severity'

sync rahul; pe $(R rahul)/hc/bin/hc 's/^readonly VERSION=1.0.0$/readonly VERSION=1.1.0/m'
commit rahul '2026-10-27 09:50' 'hc: version 1.1.0'; push rahul

sync asha; pe $A/hc/hc.conf 's|^(ENDPOINTS=.*)$|$1 copilot=http://localhost:8000/health|m'
commit asha '2026-10-27 14:10' 'hc.conf: add the Course Copilot health endpoint'; push asha

pe $P/hc/lib/report.py 's/^    payload = \{"text": f"\[\{new\}\] \{host\}: \{summary\}", "host": host,\n/    payload = {"text": f"*{new}* on {host}",\n               "blocks": [{"type": "section", "text": summary}], "host": host,\n/m'
commit priya '2026-10-28 11:30' 'notify: Slack blocks in the alert payload'; push priya feature/notify-rewrite

sync rahul; R2=$(R rahul)
pe $R2/hc/lib/checks.sh 's/^      WEBHOOK_URL\)$/      WEBHOOK_URL CERT_DAYS)/m'
pe $R2/hc/lib/checks.sh 's/^run_checks\(\) \{/check_cert() {   # TODO: days until the TLS certificate expires\n  result OK cert "not checked yet (CERT_DAYS=\$CERT_DAYS)"\n}\n\nrun_checks() {/m'
pe $R2/hc/hc.conf 's/^(HTTP_TIMEOUT=.*)$/$1\nCERT_DAYS=14/m'
for f in ok warn unknown; do pe $R2/hc/tests/$f.conf 's|^(WEBHOOK_URL=.*)$|$1\nCERT_DAYS=14|m'; done
commit rahul '2026-10-28 17:20' 'checks: certificate expiry setting (CERT_DAYS)'; push rahul

sync asha; pe $A/hc/hc.conf 's|^WEBHOOK_URL=.*$|WEBHOOK_URL=https://alerts.internal/hooks/hc|m'
commit asha '2026-10-29 12:00' 'hc.conf: the webhook moves to alerts.internal'; push asha

# ---- week 2
pe $P/hc/hc.conf 's/^(HTTP_TIMEOUT=.*)$/$1\nNOTIFY_RETRY=2\nNOTIFY_TIMEOUT=5/m'
pe $P/hc/lib/checks.sh 's/^      WEBHOOK_WARN WEBHOOK_CRIT\)$/      WEBHOOK_WARN WEBHOOK_CRIT NOTIFY_RETRY NOTIFY_TIMEOUT)/m'
for f in ok warn unknown; do pe $P/hc/tests/$f.conf 's|^(WEBHOOK_CRIT=.*)$|$1\nNOTIFY_RETRY=0\nNOTIFY_TIMEOUT=1|m'; done
commit priya '2026-11-02 10:15' 'notify: retry and timeout settings for alerts'

sync rahul; pe $(R rahul)/hc/systemd/hc.timer 's/every 5 minutes/every 2 minutes/; s|^OnCalendar=.*$|OnCalendar=*:0/2|m'
commit rahul '2026-11-02 15:40' 'timer: run hc every 2 minutes'; push rahul

sync asha; pe $A/hc/README.md 's/It sends a POST with JSON to `WEBHOOK_URL` only when the\n/It sends a POST with JSON to `WEBHOOK_URL` (HTTPS only in production) only when the\n/m'
commit asha '2026-11-03 11:10' 'README: webhooks must use HTTPS in production'; push asha

# a short-lived branch, merged the same day (left on origin afterwards: branch sprawl, later)
sync rahul; sh_as rahul "git switch -q -c fix/timer-jitter"
pe $(R rahul)/hc/systemd/hc.timer 's/^(AccuracySec=.*)$/$1\nRandomizedDelaySec=20s/m'
commit rahul '2026-11-03 14:30' 'timer: spread runs with RandomizedDelaySec'; push rahul fix/timer-jitter
sh_as rahul "git switch -q main && GIT_AUTHOR_DATE='2026-11-03 16:00 +0530' GIT_COMMITTER_DATE='2026-11-03 16:00 +0530' git merge -q --no-ff --no-edit fix/timer-jitter"; push rahul

sync rahul; pe $(R rahul)/hc/lib/http_check.py 's/^    detail = f"HTTP \{status\} in \{ms:.0f\} ms"$/    detail = f"HTTP {status} in {ms:.0f} ms"   # after redirects/m'
commit rahul '2026-11-04 09:30' 'http_check: note that redirects are followed'; push rahul

pe $P/hc/tests/run.sh 's/^(check "alert failed: no state saved" no "\$\(saved\)"\n)/$1\nbin\/hc -c tests\/warn.conf > \/dev\/null 2>&1\ncheck "WARN alert uses WEBHOOK_WARN" 1 "\$(grep -c hc-warn "\$tmp\/hc.log")"\n/m'
commit priya '2026-11-04 14:00' 'tests: cover the per-severity webhooks'

sync asha; pe $A/hc/hc.conf 's/^HTTP_TIMEOUT=3$/HTTP_TIMEOUT=5/m'
commit asha '2026-11-05 10:20' 'hc.conf: HTTP timeout 3 -> 5 seconds'; push asha

pe $P/hc/hc.conf 's/^HTTP_TIMEOUT=/CHECK_TIMEOUT=/m'
pe $P/hc/lib/checks.sh 's/ HTTP_TIMEOUT$/ CHECK_TIMEOUT/m; s/"\$HTTP_TIMEOUT"/"\$CHECK_TIMEOUT"/'
for f in ok warn unknown; do pe $P/hc/tests/$f.conf 's/^HTTP_TIMEOUT=/CHECK_TIMEOUT=/m'; done
commit priya '2026-11-06 11:00' 'notify: rename HTTP_TIMEOUT to CHECK_TIMEOUT'; push priya feature/notify-rewrite

sync rahul; R2=$(R rahul)
cp $R2/hc/tests/warn.conf $R2/hc/tests/crit.conf; pe $R2/hc/tests/crit.conf 's/^DISK_CRIT=.*$/DISK_CRIT=1/m; s/^# .*\n//m'
pe $R2/hc/tests/run.sh 's/^(check "alert failed: no state saved" no "\$\(saved\)"\n)/$1\nbin\/hc -c tests\/crit.conf > \/dev\/null 2>&1\ncheck "CRIT: exit 2" 2 \$?\n/m'
commit rahul '2026-11-06 16:30' 'tests: a CRIT config and test'; push rahul

# ---- week 3
sync asha; pe $A/hc/lib/report.py 's/f"\[\{new\}\] \{host\}: \{summary\}"/f"{host} [{new}]: {summary}"/'
commit asha '2026-11-09 11:45' 'report: put the host name first in alerts'; push asha

pe $P/hc/README.md 's/It sends a POST with JSON to `WEBHOOK_URL` only when the\n/It sends a POST with JSON to `WEBHOOK_WARN` or `WEBHOOK_CRIT` (by severity) only when the\n/m'
pe $P/hc/README.md 's/^(conf\/hc.conf  .*webhook)$/$1s, retry/m'
commit priya '2026-11-09 15:00' 'README: document the new alert settings'

sync rahul; pe $(R rahul)/hc/install.sh 's/^(put 755 "\$src\/bin\/hc".*)$/install -d -o hc -g hc -m 750 \/var\/lib\/hc\n$1/m'
commit rahul '2026-11-10 10:00' 'install.sh: create /var/lib/hc with mode 750'; push rahul

sync asha; mkdir -p $A/hc/logrotate; sed 's/weekly/daily/; s/rotate 8/rotate 14/' $T/logrotate/hc > $A/hc/logrotate/hc
commit asha '2026-11-10 14:30' 'logrotate: keep 14 days of hc logs'; push asha

sync rahul; pe $(R rahul)/hc/lib/checks.sh 's/die "missing setting \$key in \$1"/die "missing setting \$key in \$1 (see hc\/README.md)"/'
commit rahul '2026-11-11 12:15' 'checks: point to the README when a setting is missing'; push rahul

pe $P/hc/bin/hc 's/^(if \[\[ \$status != "\$previous" \]\]; then   # alert on a change, not every run\n)/hour=\$(date +%H)\nif [[ \$status == WARN \&\& ( 10#\$hour -ge 22 || 10#\$hour -lt 7 ) ]]; then\n  previous=WARN   # quiet hours: no WARN alerts at night\nfi\n$1/m'
commit priya '2026-11-11 17:00' 'notify: quiet hours, no WARN alerts at night'

sync asha; printf '\n## On call\n\nRunbook: https://wiki.example.com/ops/hc (what each alert means, and what to do).\n' >> $A/hc/README.md
commit asha '2026-11-12 10:40' 'README: link the on-call runbook'; push asha

sync rahul; pe $(R rahul)/hc/hc.conf 's/^MEM_WARN=20$/MEM_WARN=15/m'
commit rahul '2026-11-12 15:10' 'hc.conf: warn at 15% available memory'; push rahul

pe $P/hc/bin/hc 's/^readonly VERSION=1.0.0$/readonly VERSION=2.0.0/m'
commit priya '2026-11-12 18:20' 'hc: version 2.0.0 for the new alerts'

sync asha; pe $A/hc/bin/hc 's/^readonly VERSION=1.1.0$/readonly VERSION=1.2.0/m'
commit asha '2026-11-13 11:30' 'hc: version 1.2.0'; push asha

pe $P/hc/lib/report.py 's/"\*\{new\}\* on \{host\}"/"*{new}* on {host}: {summary}"/'
commit priya '2026-11-13 12:10' 'notify: include the summary in the message'; push priya feature/notify-rewrite

echo history built
