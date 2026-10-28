printf 'Host web01\n    HostName localhost\n    User asha\n    IdentityFile ~/.ssh/id_ed25519\n' > ~/.ssh/config
chmod 600 ~/.ssh/config
cat ~/.ssh/config
ssh web01 'echo $HOSTNAME'
ssh -G web01 2>/dev/null | grep -E '^(user|hostname|port|identityfile) '
find ~/site -type f
rsync -anv --delete ~/site/ web01:/srv/releases/v2.15.0/
rsync -av --delete ~/site/ web01:/srv/releases/v2.15.0/
ls -la /srv/releases/v2.15.0
echo '<h1>allcsvideos v2.15.0, checkout fix</h1>' > ~/site/index.html
rm ~/site/static/app.js
rsync -anv --delete ~/site/ web01:/srv/releases/v2.15.0/
rsync -av --delete ~/site/ web01:/srv/releases/v2.15.0/
