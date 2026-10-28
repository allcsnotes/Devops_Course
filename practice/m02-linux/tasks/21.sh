sudo lsof +L1
ps -o pid,user,cmd -p $(pgrep -f encoder.py)
systemctl status $(pgrep -f encoder.py) | head -1
sudo kill -HUP $(pgrep -f encoder.py)
@sleep 1
df -h /data
sudo lsof +L1
sudo ls -l /data/logs
