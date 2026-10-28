cd ~/rescue/13-line-endings
git status -s
git restore hc
git status -s
hc/bin/hc --version
git log --oneline -3
git ls-files --eol hc .gitattributes
git diff --stat
cat .gitattributes
echo 'hc/bin/* text eol=lf' >> .gitattributes
git add .gitattributes
git add --renormalize .
git status -s
git ls-files --eol hc
git commit -m "Normalize line endings to LF, hc/bin included"
rm hc/bin/hc hc/lib/checks.sh hc/tests/run.sh
git restore hc
git ls-files --eol hc
git status -s
hc/bin/hc --version
git push
