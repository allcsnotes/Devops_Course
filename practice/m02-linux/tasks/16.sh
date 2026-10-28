cd /var/log/nginx
cut -d' ' -f1 access.log.1 | sort | uniq -c | sort -rn | head -5
awk '$1 == "192.0.2.66" {print $6, $7, $9}' access.log.1 | sort | uniq -c
grep '^192.0.2.66 ' access.log.1 | head -n 1 | cut -d' ' -f4
grep '^192.0.2.66 ' access.log.1 | tail -n 1 | cut -d' ' -f4
