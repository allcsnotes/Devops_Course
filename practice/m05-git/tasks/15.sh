cd ~/rescue/15-bisect
hc/tests/run.sh; echo "exit $?"
git bisect start
git bisect bad
git bisect good v1.2.0
git bisect run hc/tests/run.sh
git show d8378e2 -- hc/lib/checks.sh
git bisect reset
