#!/bin/bash
# Runs as root while the image is built. Prepares web-01 the way it looked at the start of the lesson.
set -e
useradd -m -s /bin/bash -G sudo,adm asha            # Asha: the engineer, in the sudo group (like the first user on a cloud server)
echo 'asha:demo-password-123' | chpasswd            # FAKE demo password for this throwaway lab only

# The app folder Asha deployed
install -d -o asha -g asha -m 755 /srv/allcsvideos
printf '#!/bin/bash\necho "Deploying allcsvideos..."\n' > /srv/allcsvideos/deploy.sh
printf 'DB_USER=allcs\nDB_PASSWORD=demo-password-123   # fake\n' > /srv/allcsvideos/app.env
chown asha:asha /srv/allcsvideos/deploy.sh /srv/allcsvideos/app.env
chmod 664 /srv/allcsvideos/deploy.sh /srv/allcsvideos/app.env

# The uploads folder, created by a deploy script that ran as root (the lesson's bug)
install -d -m 755 /var/www/allcsvideos/uploads
for i in 1 2 3; do head -c 2097152 /dev/urandom > /var/www/allcsvideos/uploads/lesson-0$i.mp4; done
chmod 644 /var/www/allcsvideos/uploads/*
head -c 3145728 /dev/urandom > /tmp/lesson-04.mp4 && chmod 644 /tmp/lesson-04.mp4   # Meera's new upload, staged in /tmp

# Last night's backup of the uploads (used to restore after the staged vandalism)
install -d -m 700 /var/backups/uploads && cp -p /var/www/allcsvideos/uploads/*.mp4 /var/backups/uploads/
