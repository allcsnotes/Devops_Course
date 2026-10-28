cd ~/rescue/17-ready-for-review
git log --oneline origin/main..
git log -p origin/main.. | grep -n demo-token
sed -i 's|^WEBHOOK_TEAM=.*|WEBHOOK_TEAM=http://hooks:9000/hc-team|' hc/hc.conf
git commit -a --fixup=417d186
git log --oneline origin/main..
@rm -rf /tmp/todo-copy && cp -a . /tmp/todo-copy
# the to-do list nano would open (printed from a scratch copy of the repository):
(cd /tmp/todo-copy && GIT_SEQUENCE_EDITOR='grep -v -e "^#" -e "^$"' git rebase -i --autosquash origin/main 2>/dev/null)
GIT_SEQUENCE_EDITOR="sed -i 's/^pick \(.*\) wip$/fixup \1 wip/'" git rebase -i --autosquash origin/main
git log --oneline origin/main..
git log -p origin/main.. | grep -c demo-token
git show --format='%h %s' HEAD
hc/bin/hc
git push -u origin feature/team-webhook
