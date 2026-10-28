#!/bin/bash
# Run as root in the build box. asha's login shell talks to the box's own Docker engine over TLS (port 2376),
# Packer keeps its temporary files on a folder that the engine sees at the same path (shared volume).
set -e
chmod 1777 /packer-tmp
cat > /etc/profile.d/build.sh <<'P'
export DOCKER_HOST=tcp://docker:2376 DOCKER_TLS_VERIFY=1 DOCKER_CERT_PATH=/certs/client
export PACKER_TMP_DIR=/packer-tmp
export PS1='\[\e[1;34m\]\u@\h\[\e[0m\]:\[\e[1;36m\]\w\[\e[0m\]$ '
P
su - asha -c 'git config --global user.name Asha; git config --global user.email asha@example.com; git config --global init.defaultBranch main'
