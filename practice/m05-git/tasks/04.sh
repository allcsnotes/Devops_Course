cd ~/rescue/04-reset-too-far
git log --oneline -2
git status -sb
git reflog -5
git reset --hard HEAD@{1}
git log --oneline -4
git reset --hard HEAD~1
git log --oneline -3
git status -sb
