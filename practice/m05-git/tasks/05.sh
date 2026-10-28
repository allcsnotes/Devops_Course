cd ~/rescue/05-deleted-branch
git branch -a
git reflog -6
git branch spike/json-alerts 50c5d8e
git log --oneline main..spike/json-alerts
git show spike/json-alerts:hc/lib/json.sh
