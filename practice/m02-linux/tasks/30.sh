systemctl --failed
systemctl is-active nginx allcsvideos-api allcsvideos-encoder ssh
systemctl is-enabled allcsvideos-api allcsvideos-reindex
uptime
df -h /data
sudo lsof +L1
sudo find /var/www -perm -o+w ! -type l
sudo visudo -c | grep -v 'parsed OK'
sudo sshd -t && echo sshd config OK
ssh web01 hostname
curl -s localhost | grep -o '<title>.*</title>'
curl -s localhost/robots.txt | head -n 1
curl -s localhost/api/health
sudo -u priya sudo -n nginx -t 2>&1 | tail -n 1
id priya
