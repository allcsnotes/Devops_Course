ls -ld /srv/releases
sudo -u priya touch /srv/releases/priya-test
sudo chgrp devs /srv/releases
sudo chmod 2775 /srv/releases
ls -ld /srv/releases
sudo -u priya touch /srv/releases/priya-test
ls -l /srv/releases
sudo rm /srv/releases/priya-test
