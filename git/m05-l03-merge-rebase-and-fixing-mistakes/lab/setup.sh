#!/bin/bash
# setup.sh (runs as root inside the git-team container): rebuilds the allcsvideos-ops team history up to the end of M05-L02,
# then adds the starting point of this lesson. History built FOR THE DEMO, with deliberate dates (IST).
#  1. /opt/history.sh: the M05-L02 history script, copied unchanged (Oct 21 - Nov 13, 2026; bare origin + 3 clones).
#  2. The M05-L02 on-screen steps on allcsvideos-ops, replayed with the same commands (Nov 16 - 17).
#  3. New for M05-L03: tag v1.2.0 + branch release/1.2 (what the servers run), and Priya's local feature/cert-check.
set -euo pipefail
bash /opt/history.sh
# Asha pushed without -u in M05-L02 (her pulls named origin main): give her main its upstream, like the clones have
runuser -l asha -c "cd ~/allcsvideos-ops && git fetch -q origin && git branch -q -u origin/main main"
O=/srv/git/allcsvideos-ops.git
# git init --shared=group also turns on receive.denyNonFastForwards. GitHub allows force-pushes unless a branch is
# protected, so origin does too (the protection is switched on, for real, in this lesson's pitfalls)
git config -f $O/config receive.denyNonFastForwards false
# as USER 'YYYY-MM-DD HH:MM' 'commands' : run commands in USER's clone with that author/committer date
as(){ local u=$1 d="$2 +0530"; shift 2; runuser -l "$u" -c "cd ~/allcsvideos-ops && export GIT_AUTHOR_DATE='$d' GIT_COMMITTER_DATE='$d' && $*"; }

# ---- 2. M05-L02 replay: GitHub flow (Mon Nov 16), trunk-based + NOTIFY_V2 flag (Tue Nov 17), branch cleanup
as priya '2026-11-16 10:02' "git switch -q main && git pull -q && git switch -q -c fix/storefront-https"
as priya '2026-11-16 10:06' "sed -i 's|storefront=http://localhost/|storefront=https://localhost/|' hc/hc.conf && git commit -qam 'hc.conf: check the storefront over HTTPS' && git push -q -u origin fix/storefront-https"
as rahul '2026-11-16 11:26' "git fetch -q && git switch -q main && git pull -q && git merge -q --no-ff --no-edit origin/fix/storefront-https && git push -q && git push -q origin --delete fix/storefront-https"
as priya '2026-11-16 11:42' "git switch -q main && git pull -q && git branch -q -d fix/storefront-https"
as rahul '2026-11-17 09:22' "sed -i 's/^LOAD_WARN=1.5/LOAD_WARN=2/' hc/hc.conf && git commit -qam 'hc.conf: warn at load 2 per CPU' && git push -q"
runuser -l priya -c "bash /opt/flag-edit.sh"
as priya '2026-11-17 09:30' "echo 'NOTIFY_V2=off' | tee -a hc/hc.conf hc/tests/*.conf >/dev/null && sed -i 's/ CERT_DAYS)/ CERT_DAYS NOTIFY_V2)/' hc/lib/checks.sh && git commit -qam 'notify: NOTIFY_V2 flag, off by default' && git pull -q --rebase && git push -q"
as priya '2026-11-17 10:32' "git fetch -q --prune && git push -q origin --delete fix/timer-jitter"

# ---- 3. what the servers run: v1.2.0 (Asha's 'hc: version 1.2.0' commit of Nov 13) and a release branch for patches
as asha '2026-11-13 11:40' "git switch -q main && git pull -q && V=\$(git log --format=%h --grep='^hc: version 1.2.0\$' -1) && git tag -a v1.2.0 -m 'hc 1.2.0' \$V && git branch release/1.2 \$V && git push -q origin v1.2.0 release/1.2"
for u in priya rahul; do runuser -l $u -c "cd ~/allcsvideos-ops && git fetch -q --tags"; done

# Priya's local branch for the certificate check (never pushed): four small commits, Tue Nov 17 - Wed Nov 18
P=/home/priya/allcsvideos-ops
as priya '2026-11-17 11:00' "git switch -q main && git pull -q && git switch -q -c feature/cert-check"
perl -0pi -e 's/^check_cert\(\) \{   # TODO: days until the TLS certificate expires\n  result OK cert "not checked yet \(CERT_DAYS=\$CERT_DAYS\)"\n\}/check_cert() {   # days until the TLS certifcate of host \$1 expires\n  local end days\n  end=\$(openssl s_client -connect "\$1:443" -servername "\$1" <\/dev\/null 2>\/dev\/null | openssl x509 -noout -enddate | cut -d= -f2)\n  days=\$(( (\$(date -d "\$end" +%s) - \$(date +%s)) \/ 86400 ))\n  if (( days <= CERT_DAYS )); then result WARN "cert \$1" "expires in \$days days"\n  else result OK "cert \$1" "\$days days left"; fi\n}/m' $P/hc/lib/checks.sh
sed -i 's/^CERT_DAYS=14$/CERT_DAYS=21/' $P/hc/hc.conf; chown -R priya:priya $P
as priya '2026-11-17 11:40' "git commit -qam 'checks: add check_cert'"
perl -0pi -e 's/^(  check_load\n)/$1  # TODO: check_cert for every HTTPS endpoint\n/m' $P/hc/lib/checks.sh; chown -R priya:priya $P
as priya '2026-11-17 16:10' "git commit -qam 'wip'"
sed -i 's/certifcate/certificate/' $P/hc/lib/checks.sh; chown -R priya:priya $P
as priya '2026-11-18 10:05' "git commit -qam 'fix typo'"
printf '\n## Certificates\n\n`CERT_DAYS`: WARN when a TLS certificate expires in this many days or fewer.\n' >> $P/hc/README.md; chown -R priya:priya $P
as priya '2026-11-18 10:20' "git commit -qam 'docs'"
as priya '2026-11-18 10:21' "git switch -q main"
echo setup done
