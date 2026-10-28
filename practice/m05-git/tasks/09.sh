cd ~/rescue/09-squash
git log --oneline origin/main..
GIT_SEQUENCE_EDITOR="sed -i '2,4s/^pick/fixup/'" git rebase -i HEAD~4
git log --oneline origin/main..
git diff ORIG_HEAD HEAD --stat
git show --stat --format='%h %an %ad%n%s' HEAD
git push -u origin feature/cert-hosts
