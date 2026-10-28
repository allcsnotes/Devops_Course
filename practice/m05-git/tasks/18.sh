cd ~/rescue/18-ship-1.3.1
git tag --contains d8378e2
git revert --no-edit d8378e2
hc/tests/run.sh
git push
git switch -c release/1.3 v1.3.0
git cherry-pick -x main
sed -i 's/^readonly VERSION=1.3.0/readonly VERSION=1.3.1/' hc/bin/hc
git commit -am "hc: version 1.3.1"
hc/tests/run.sh
hc/bin/hc --version
git tag -a v1.3.1 -m "hc 1.3.1"
git log --oneline --graph --all -6
git push -u origin release/1.3 v1.3.1
git log --format='%h %s%n%b' -2 | grep -v '^$'
git describe
