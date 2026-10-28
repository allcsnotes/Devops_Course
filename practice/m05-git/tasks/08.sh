cd ~/rescue/08-bad-rebase
git status
grep -n -A3 '^CERT_DAYS' hc/hc.conf
git rebase --abort
git status
git log --oneline --graph -4
grep -n '^CERT_DAYS' hc/hc.conf
git reflog -1 feature/cert-check
