cd ~/rescue/07-merge-conflict
git status
sed -n '/^<<<<<<<.*/,/^>>>>>>>.*/p' hc/hc.conf
git config merge.conflictstyle zdiff3
git checkout --merge hc/hc.conf
sed -n '/^<<<<<<<.*/,/^>>>>>>>.*/p' hc/hc.conf
git checkout --theirs hc/hc.conf
sed -i 's/^DISK_CRIT=90$/DISK_CRIT=95/' hc/hc.conf
grep -n '^DISK' hc/hc.conf
grep -c -E '^(<<<<<<<|\|\|\|\|\|\|\||=======|>>>>>>>)' hc/hc.conf
hc/bin/hc
git add hc/hc.conf
git status -s
git commit --no-edit
git log --oneline --graph -4
