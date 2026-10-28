cd ~/rescue/14-hotfix
git log --oneline v1.2.0..main
git switch release/1.2
printf 'DISK_WARN=80\n  # an indented comment\n' > /tmp/indented.conf
hc/bin/hc -c /tmp/indented.conf; echo "exit $?"
git cherry-pick -x b1026bb
sed -i 's/^readonly VERSION=1.2.0/readonly VERSION=1.2.1/' hc/bin/hc
git commit -am "hc: version 1.2.1"
hc/bin/hc -c /tmp/indented.conf; echo "exit $?"
hc/bin/hc --version
git log --format='%h %s%n%b' -2 | grep -v '^$'
git tag -a v1.2.1 -m "hc 1.2.1"
git describe
git log --oneline -4
git push origin release/1.2 v1.2.1
