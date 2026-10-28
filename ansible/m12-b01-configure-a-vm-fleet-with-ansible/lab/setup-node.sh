#!/bin/bash
# Run as root inside each server right after it boots. $1 = Asha's public key (one line).
# Leaves the server BARE, like a fresh cloud VM: its own host keys, the stock sshd config, and one default user
# (asha, with her key and passwordless sudo, the way cloud images set up "ubuntu" on EC2). Ansible does the rest.
set -e
rm -f /etc/ssh/ssh_host_* && ssh-keygen -A >/dev/null       # every server gets its own host keys
useradd -m -s /bin/bash -G sudo asha
echo 'asha ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-cloud-init-users && chmod 440 /etc/sudoers.d/90-cloud-init-users
install -d -m 700 -o asha -g asha /home/asha/.ssh
echo "$1" > /home/asha/.ssh/authorized_keys && chown asha:asha /home/asha/.ssh/authorized_keys && chmod 600 /home/asha/.ssh/authorized_keys
install -d /run/sshd && sshd -t && systemctl restart ssh
