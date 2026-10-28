#!/bin/bash
# Runs as root inside each server (bastion, web-01, db-01) right after it boots. up.sh calls it.
set -e
rm -f /etc/ssh/ssh_host_*                     # the image was built once: give every server its own host keys
ssh-keygen -A >/dev/null
useradd -m -s /bin/bash -G sudo,adm asha
echo 'asha:demo-password-123' | chpasswd      # FAKE demo password, this throwaway lab only
useradd -m -s /bin/bash priya
echo 'priya:demo-priya-pass' | chpasswd       # FAKE demo password, this throwaway lab only
