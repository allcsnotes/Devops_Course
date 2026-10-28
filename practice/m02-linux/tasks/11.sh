pid=$(pgrep -u priya python3)
echo $pid
kill $pid
sudo kill $pid
@sleep 1
pgrep -a -u priya python3
systemctl status $(pgrep -u priya python3) | head -3
systemctl cat allcsvideos-reindex
sudo systemctl disable --now allcsvideos-reindex
systemctl is-active allcsvideos-reindex
systemctl is-enabled allcsvideos-reindex
pgrep -a -u priya python3
