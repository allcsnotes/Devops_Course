cd ~/rescue/10-pushed-bad-commit
git log --oneline -3
hc/bin/hc; echo "exit $?"
git status -sb
git revert --no-edit HEAD
hc/bin/hc; echo "exit $?"
git log --oneline -3
git show --format='%s%n%n%b' --stat HEAD
git push
git status -sb
