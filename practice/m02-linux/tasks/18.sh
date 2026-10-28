cd /var/log/nginx
grep -c 'shell.php' access.log.1
grep 'shell.php' access.log.1 | awk '{print $1, $4, $7, $9}'
grep '^192.0.2.14 ' access.log.1 | awk '{print $4, $7, $9}'
grep -E '\.php|/\.env' access.log.1 | cut -d' ' -f1 | sort -u
