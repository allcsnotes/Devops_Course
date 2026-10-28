cd ~/rescue/11-secret
git status -sb
git show --stat --format='%h %s' HEAD
git grep -n token
sed -i 's|^WEBHOOK_URL=.*|WEBHOOK_URL=http://hooks:9000/hc|' hc/hc.conf
git diff
git commit -a --amend --no-edit
git show --stat --format='%h %s' HEAD
git log -p origin/main..HEAD | grep -c demo-token
git grep -n token
hc/bin/hc
git push -u origin feature/chat-alerts
