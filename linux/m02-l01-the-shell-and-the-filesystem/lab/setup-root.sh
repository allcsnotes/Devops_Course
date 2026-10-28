#!/bin/bash
# Runs as root while the image is built. Prepares web-01 the way it looked at the start of the lesson.
set -e
useradd -m -s /bin/bash -G adm asha            # adm: Ubuntu's log-reading group (the default first user is in it)
install -d /var/www/allcsvideos
install -m 644 /tmp/site/index.html /var/www/allcsvideos/index.html
install -m 644 /tmp/site/allcsvideos /etc/nginx/sites-available/allcsvideos   # written, but NOT enabled (the lesson's bug)
