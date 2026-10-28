#!/bin/bash
# l01-repo.sh (runs as asha inside the lab container): rebuilds ~/allcsvideos-ops exactly as lesson M05-L01 left it,
# with the same files, commits, branches and tags (your commit hashes differ from the video: they include the time).
# Uses the toolkit's README and hc.conf from /opt/hc-toolkit. The webhook token below is FAKE, on purpose (M05-L01 pitfall 1).
set -euo pipefail
cd ~ && mkdir allcsvideos-ops && cd allcsvideos-ops && git init -q
printf '# allcsvideos-ops\nOps scripts and configs for allcsvideos.com\n' > README.md
mkdir hc && cp /opt/hc-toolkit/README.md /opt/hc-toolkit/conf/hc.conf hc/
git add . && git commit -qm 'Add README and hc toolkit config'
sed -i 's/^SERVICES=.*/SERVICES=nginx allcsvideos-api course-copilot/' hc/hc.conf
git commit -qam 'hc: also check course-copilot'
git branch alerts-v2
git tag v0.1 HEAD~1
git tag -a v0.2 -m 'hc config with course-copilot'
sed -i 's/^DISK_WARN=80/DISK_WARN=75/' hc/hc.conf
git commit -qam 'hc: warn at 75% disk'
echo 'Toolkit docs: hc/README.md' >> README.md
git commit -qam 'README: link the toolkit docs'
# the detached-HEAD commit, rescued as readme-owner
git switch -q --detach v0.1
echo 'Owner: the allcsvideos ops team' >> README.md
git commit -qam 'README: add the owner'
git branch readme-owner
git switch -q main
# pitfall 1: a (fake) token committed and removed
sed -i 's|^WEBHOOK_URL=.*|WEBHOOK_URL=https://hooks.example.com/FAKE-demo-token-123|' hc/hc.conf
git commit -qam 'hc: use the team webhook'
sed -i 's|^WEBHOOK_URL=.*|WEBHOOK_URL=http://hooks:9000/hc|' hc/hc.conf
git commit -qam 'hc: remove the webhook token'
# pitfall 2: .gitignore (the .env and hc.log files stay untracked)
echo 'WEBHOOK_URL=https://hooks.example.com/FAKE-demo-token-123' > .env
echo 'run at 19:02 OK' > hc.log
printf '.env\n*.log\n' > .gitignore
git add .gitignore && git commit -qm 'Ignore .env and log files'
# pitfall 4: LF line endings for scripts
echo '*.sh text eol=lf' > .gitattributes
printf '#!/bin/bash\necho ok\n' > hc/check.sh && chmod +x hc/check.sh
git add .gitattributes hc/check.sh && git commit -qm 'Add check.sh, LF line endings for scripts'
echo "allcsvideos-ops rebuilt as M05-L01 left it"
