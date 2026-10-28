ls -lh /data/logs
sudo gzip /data/logs/api.log.1
ls -lh /data/logs
df -h /data
sudo zcat /data/logs/api.log.1.gz | tail -n 2
