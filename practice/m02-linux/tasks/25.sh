ssh -o BatchMode=yes localhost hostname
@sleep 2
systemctl is-active ssh.socket ssh
journalctl -u ssh -n 3
sudo sshd -t
@sleep 10
sudo sed -i 's/KbdInteractiveAuthenticaton/KbdInteractiveAuthentication/' /etc/ssh/sshd_config.d/10-hardening.conf
sudo sshd -t
sudo install -d -m 755 /run/sshd
sudo sshd -t && echo syntax OK
sudo systemctl restart ssh
systemctl is-active ssh.socket ssh
sudo sshd -T | grep -E '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|allowusers)'
