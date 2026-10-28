# a teammate's clone that pulled the broken state (35880f1) before the fix was pushed
@rm -rf ~/teammate-13 && git clone -q --no-local /srv/git/s13/allcsvideos-ops.git ~/teammate-13 && cd ~/teammate-13 && git reset -q --hard 35880f1
cd ~/teammate-13
git status -s
git pull
git fetch
git reset --hard origin/main
git status -s
hc/bin/hc --version
@cd ~ && rm -rf ~/teammate-13
