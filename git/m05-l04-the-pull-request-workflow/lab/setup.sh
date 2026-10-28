#!/bin/bash
# setup.sh (runs as root inside the git-team container): rebuilds the allcsvideos-ops team history up to where M05-L02/L03 start,
# FOR THE DEMO, with deliberate dates (IST), exactly like M05-L03's setup.sh parts 1-3:
#  1. /opt/history.sh (the M05-L02 history script; bare origin in /srv/git + 3 clones)
#  2. the M05-L02 on-screen steps (GitHub flow fix, NOTIFY_V2 flag, branch cleanup)
#  3. tag v1.2.0 + branch release/1.2 (what the servers run)
# Only difference: every date is shifted by LAB_SHIFT=-30 days, so the history ends the day before this lesson was
# recorded (2026-10-20), so the Gitea web UI shows sensible relative times ("2 days ago", not "in 4 weeks").
set -euo pipefail
export LAB_SHIFT=-30
bash /opt/history.sh
runuser -l asha -c "cd ~/allcsvideos-ops && git fetch -q origin && git branch -q -u origin/main main"
O=/srv/git/allcsvideos-ops.git
git config -f $O/config receive.denyNonFastForwards false
as(){ local u=$1 d; d=$(date -d "$2 +0530 $LAB_SHIFT days" '+%Y-%m-%d %H:%M:%S +0530'); shift 2; runuser -l "$u" -c "cd ~/allcsvideos-ops && export GIT_AUTHOR_DATE='$d' GIT_COMMITTER_DATE='$d' && $*"; }
as priya '2026-11-16 10:02' "git switch -q main && git pull -q && git switch -q -c fix/storefront-https"
as priya '2026-11-16 10:06' "sed -i 's|storefront=http://localhost/|storefront=https://localhost/|' hc/hc.conf && git commit -qam 'hc.conf: check the storefront over HTTPS' && git push -q -u origin fix/storefront-https"
as rahul '2026-11-16 11:26' "git fetch -q && git switch -q main && git pull -q && git merge -q --no-ff --no-edit origin/fix/storefront-https && git push -q && git push -q origin --delete fix/storefront-https"
as priya '2026-11-16 11:42' "git switch -q main && git pull -q && git branch -q -d fix/storefront-https"
as rahul '2026-11-17 09:22' "sed -i 's/^LOAD_WARN=1.5/LOAD_WARN=2/' hc/hc.conf && git commit -qam 'hc.conf: warn at load 2 per CPU' && git push -q"
runuser -l priya -c "bash /opt/flag-edit.sh"
as priya '2026-11-17 09:30' "echo 'NOTIFY_V2=off' | tee -a hc/hc.conf hc/tests/*.conf >/dev/null && sed -i 's/ CERT_DAYS)/ CERT_DAYS NOTIFY_V2)/' hc/lib/checks.sh && git commit -qam 'notify: NOTIFY_V2 flag, off by default' && git pull -q --rebase && git push -q"
as priya '2026-11-17 10:32' "git fetch -q --prune && git push -q origin --delete fix/timer-jitter"
as asha '2026-11-13 11:40' "git switch -q main && git pull -q && V=\$(git log --format=%h --grep='^hc: version 1.2.0\$' -1) && git tag -a v1.2.0 -m 'hc 1.2.0' \$V && git branch release/1.2 \$V && git push -q origin v1.2.0 release/1.2"
for u in priya rahul; do runuser -l $u -c "cd ~/allcsvideos-ops && git fetch -q --tags"; done
echo setup done
