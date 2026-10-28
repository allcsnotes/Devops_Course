head -c 6291456 /dev/urandom > /tmp/lesson-04.mp4
ls -lh /tmp/lesson-04.mp4
curl -s -X POST --data-binary @/tmp/lesson-04.mp4 'localhost/api/upload?name=lesson-04.mp4' | grep title
tail -n 1 /var/log/nginx/error.log
grep -Rn client_max_body_size /etc/nginx/sites-enabled/
sudo sed -i.bak 's/client_max_body_size 1m;/client_max_body_size 64m;/' /etc/nginx/sites-available/allcsvideos
diff /etc/nginx/sites-available/allcsvideos.bak /etc/nginx/sites-available/allcsvideos
sudo nginx -t
sudo systemctl reload nginx
@sleep 1
curl -s -X POST --data-binary @/tmp/lesson-04.mp4 'localhost/api/upload?name=lesson-04.mp4'
ls -lh /data/uploads
df -h /data
