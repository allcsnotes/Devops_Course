cd ~/rescue/02-detached-head
git status
git log --all --oneline | grep -c owner
git reflog -4
git branch readme-owner 238e215
git log --oneline --graph --all -6
git log --oneline -2 readme-owner
