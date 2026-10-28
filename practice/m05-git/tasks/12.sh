cd ~/rescue/12-force-push
git status -sb
git pull
git status -sb
git log --oneline --graph --all -9
git pull --rebase
git log --oneline --graph -6
git push
