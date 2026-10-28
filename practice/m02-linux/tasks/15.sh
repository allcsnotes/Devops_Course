cd /var/log/nginx
ls -lh access.log.1
wc -l < access.log.1
head -n 1 access.log.1
cut -d' ' -f9 access.log.1 | sort | uniq -c | sort -rn
