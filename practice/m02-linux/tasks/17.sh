cd /var/log/nginx
awk '$9 >= 500' access.log.1 | wc -l
awk '$9 >= 500 {print $9, $6, $7}' access.log.1 | cut -d'?' -f1 | sort | uniq -c | sort -rn
awk '$9 == 507' access.log.1 | head -n 1 | cut -d' ' -f4
awk '$9 == 502' access.log.1 | head -n 1 | cut -d' ' -f4
awk '$9 == 502' access.log.1 | tail -n 1 | cut -d' ' -f4
