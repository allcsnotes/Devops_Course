cd ~/rescue/16-lost-after-force-push
git status -sb
git log --oneline -4
git reflog -5
git reset --hard HEAD@{1}
git log --oneline --graph --all -8
git pull --rebase
git log --oneline --graph -6
hc/bin/hc
grep -n -A3 '^route()' hc/lib/checks.sh
git push
