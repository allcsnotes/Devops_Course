systemctl show -p MainPID --value allcsvideos-api
sudo kill -9 $(systemctl show -p MainPID --value allcsvideos-api)
systemctl is-active allcsvideos-api
@sleep 2
systemctl is-active allcsvideos-api
systemctl show -p MainPID --value allcsvideos-api
journalctl -u allcsvideos-api -n 5
curl -s localhost/api/health
