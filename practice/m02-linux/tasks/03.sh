sudo ln -s /etc/nginx/sites-available/allcsvideos /etc/nginx/sites-enabled/allcsvideos
sudo rm /etc/nginx/sites-enabled/default
ls -l /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
@sleep 1
curl -s localhost | grep title
curl -s -i localhost/api/health | head -1
