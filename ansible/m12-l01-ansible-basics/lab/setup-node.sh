#!/bin/bash
# Run as root inside each managed node right after it boots. $1 = Asha's public key (one line).
set -e
rm -f /etc/ssh/ssh_host_* && ssh-keygen -A >/dev/null       # every server gets its own host keys
useradd -m -s /bin/bash -G sudo asha
# Passwordless sudo for asha, the way cloud images set up their default user (ubuntu on EC2). Lab only.
echo 'asha ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-asha && chmod 440 /etc/sudoers.d/90-asha
install -d -m 700 -o asha -g asha /home/asha/.ssh
echo "$1" > /home/asha/.ssh/authorized_keys && chown asha:asha /home/asha/.ssh/authorized_keys && chmod 600 /home/asha/.ssh/authorized_keys
# hardening from M02-L06: keys only, no root
printf 'PermitRootLogin no\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nAllowUsers asha\n' > /etc/ssh/sshd_config.d/10-hardening.conf
install -d /run/sshd && sshd -t && systemctl restart ssh
