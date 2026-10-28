sudo sed -i 's#/usr/bin/pyhton3#/usr/bin/python3#' /etc/systemd/system/allcsvideos-api.service
grep ExecStart /etc/systemd/system/allcsvideos-api.service
sudo systemctl daemon-reload
sudo systemctl restart allcsvideos-api
@sleep 1
systemctl status allcsvideos-api
curl -s localhost:8080/health
curl -s localhost/api/courses
