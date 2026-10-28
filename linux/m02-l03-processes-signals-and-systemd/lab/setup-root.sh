#!/bin/bash
# Runs as root while the image is built. Prepares web-01 the way it looked at the start of the lesson.
set -e
useradd -m -s /bin/bash -G sudo,adm asha
echo 'asha:demo-password-123' | chpasswd            # FAKE demo password for this throwaway lab only
useradd -m -s /bin/bash priya
install -d -m 755 /opt/allcsvideos
install -m 755 /tmp/files/api.py /opt/allcsvideos/api.py
install -o asha -g asha -m 755 /tmp/files/worker.sh /home/asha/worker.sh
install -o asha -g asha -m 644 /tmp/files/zombie.py /home/asha/zombie.py
