find /var/www -perm -o+w
ls -la /var/www/allcsvideos/uploads
cat /var/www/allcsvideos/uploads/shell.php
sudo rm /var/www/allcsvideos/uploads/shell.php
sudo chown -R www-data:www-data /var/www/allcsvideos/uploads
sudo find /var/www/allcsvideos/uploads -type d -exec chmod 750 {} \;
sudo find /var/www/allcsvideos/uploads -type f -exec chmod 640 {} \;
sudo ls -la /var/www/allcsvideos/uploads
sudo -u www-data touch /var/www/allcsvideos/uploads/thumb-dsa.jpg
sudo -u nobody touch /var/www/allcsvideos/uploads/evil.php
curl -s -i localhost/uploads/thumb-devops.jpg | head -1
sudo find /var/www -perm -o+w ! -type l
