cd /var/log/nginx
grep -c '^203.0.113.25 ' access.log.1
grep '^203.0.113.25 ' access.log.1 | awk '{print $1, $4, $7, $9}' | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/\1.x/' | sed 's/\[//; s#/api/upload?name=##'
grep '^203.0.113.25 ' access.log.1 | awk '{print $1, $4, $7, $9}' | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/\1.x/' | sed 's/\[//; s#/api/upload?name=##' > ~/meera-uploads.txt
wc -l ~/meera-uploads.txt
