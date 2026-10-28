sudo visudo -c
sudo -l -U priya
sudo -u priya sudo -n nginx -t
which nginx
sudo EDITOR='sed -i s#/usr/bin/nginx#/usr/sbin/nginx#g' visudo -f /etc/sudoers.d/priya-nginx
sudo chmod 0440 /etc/sudoers.d/priya-nginx
sudo cat /etc/sudoers.d/priya-nginx
sudo visudo -c
sudo -u priya sudo -n nginx -t
sudo -u priya sudo -n cat /etc/shadow
