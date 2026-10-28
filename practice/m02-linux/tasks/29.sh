sudo grep -rl DB_PASSWORD /srv /opt /home /var/backups /var/www /tmp /etc
sudo ls -li /srv/allcsvideos/app.env /home/priya/app.env.old /var/backups/app.env.save
sudo -u priya cat /home/priya/app.env.old
sudo -u priya grep DB_PASSWORD /var/backups/app.env.save
sudo rm /home/priya/app.env.old /var/backups/app.env.save
ls -li /srv/allcsvideos/app.env
sudo grep -rl DB_PASSWORD /srv /opt /home /var/backups /var/www /tmp /etc
curl -s localhost/api/health
