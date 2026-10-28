ssh -o BatchMode=yes localhost hostname
ssh -v -o BatchMode=yes localhost hostname 2>&1 | grep -E 'Offering|Authentications that can continue'
sudo journalctl -u ssh | grep -i refused
ls -ld ~/.ssh
ls -l ~/.ssh
chmod 700 ~/.ssh
ssh -o BatchMode=yes localhost hostname
ssh -v -o BatchMode=yes localhost true 2>&1 | grep -E 'Server accepts key|Authenticated'
