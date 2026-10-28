cd ~/rescue/01-wrong-branch
git status -sb
git log --oneline -3
git branch fix/disk-thresholds
git reset --hard origin/main
git switch fix/disk-thresholds
git log --oneline --graph --all -4
git status -sb
git push -u origin fix/disk-thresholds
