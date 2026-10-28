#!/bin/bash
# Run as asha on the control node (after ssh-add). Builds ~/allcs-ansible from mutable/v1 as a git repo,
# trusts the two web servers' host keys (in real life: compare fingerprints first, M12-L01), installs the
# pinned collection and applies release 1 to web-01 and web-02: the starting point of the lesson.
set -e
M=~/m12-l03-mutable-vs-immutable-infrastructure/mutable
git config --global user.name Asha; git config --global user.email asha@example.com; git config --global init.defaultBranch main
rm -rf ~/allcs-ansible && cp -r $M/v1 ~/allcs-ansible && cd ~/allcs-ansible
git init -q && git add -A && git commit -qm "release 1: web fleet (roles from M12-L02)"
ssh-keyscan -t ed25519 10.0.123.11 10.0.123.12 2>/dev/null >> ~/.ssh/known_hosts
ansible-galaxy collection install -r requirements.yml >/dev/null
ansible-playbook site.yml | tail -4
