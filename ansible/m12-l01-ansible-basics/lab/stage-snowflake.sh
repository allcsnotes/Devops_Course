#!/bin/bash
# STAGED drift (M12-L01 hook): run as root on web-02. It plays the server someone set up by hand weeks ago,
# following the wiki checklist, and then changed by hand during a late-night debugging session.
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq nginx >/dev/null
printf '<h1>allcsvideos</h1>\n<p>maintenance - back soon</p>\n' > /var/www/html/index.html
systemctl disable --now nginx 2>/dev/null
