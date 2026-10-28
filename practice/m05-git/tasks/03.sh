cd ~/rescue/03-amend
git status -sb
git log --oneline -2
git add README.md
git commit --amend -m "hc.conf: warn at 15% memory left"
git show --stat --format='%h %s' HEAD
git status -sb
