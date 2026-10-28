# imm-build: Asha's image-build box (what a CI runner would be). Packer itself comes from the official,
# pinned HashiCorp image (Packer 1.16.1, BUSL-1.1). Added: the docker CLI (the Docker builder drives a Docker engine
# through the mounted socket), Ansible in a venv (Packer's Ansible provisioner runs ansible-playbook on THIS box),
# an SSH client (the provisioner talks to the build container through Packer's local SSH proxy), tmux for captures.
FROM hashicorp/packer:1.16.1
RUN apk add --no-cache git docker-cli python3 py3-pip openssh-client bash tmux curl jq sudo shadow tree ncurses \
 && python3 -m venv /opt/ansible && /opt/ansible/bin/pip install -q ansible-core==2.21.5 \
 && /opt/ansible/bin/ansible-galaxy collection install -p /usr/share/ansible/collections ansible.posix:2.2.2 \
 && ln -s /opt/ansible/bin/ansible* /usr/local/bin/ \
 && adduser -D -s /bin/bash asha
ENTRYPOINT []
CMD ["sleep", "infinity"]
