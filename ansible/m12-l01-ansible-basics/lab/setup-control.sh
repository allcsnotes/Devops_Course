#!/bin/bash
# Run as root in the control node. Creates asha and her ed25519 key (FAKE demo passphrase, sandbox only).
# With "install" as $1 it also installs Ansible into ~/.venvs/ansible (pinned), for labs that start after M12-L01.
set -e
id asha >/dev/null 2>&1 || useradd -m -s /bin/bash asha
su - asha -c 'test -f ~/.ssh/id_ed25519 || ssh-keygen -q -t ed25519 -C asha@example.com -N demo-passphrase-123 -f ~/.ssh/id_ed25519'
su - asha -c 'grep -q "venvs/ansible" ~/.bashrc || echo "export PATH=\$HOME/.venvs/ansible/bin:\$PATH" >> ~/.bashrc'
if [ "$1" = install ]; then
  su - asha -c 'python3 -m venv ~/.venvs/ansible && ~/.venvs/ansible/bin/pip install -q ansible-core==2.21.5 ansible-lint==26.10.1'
fi
