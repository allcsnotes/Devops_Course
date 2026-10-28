#!/bin/bash
# STAGED for the M12-L02 hook. Run as asha on the control node (this lesson folder copied to ~/m12-l02-ansible-in-practice).
# Builds ~/allcs-ansible as a git repository whose history shows lesson one's web.yml growing into a
# ~300-line site.yml with copy-pasted plays and a plaintext (FAKE) database password. Dates are in the past.
set -e
H=~/m12-l02-ansible-in-practice/stages
git config --global user.name Asha; git config --global user.email asha@example.com; git config --global init.defaultBranch main
rm -rf ~/allcs-ansible; mkdir ~/allcs-ansible; cd ~/allcs-ansible; git init -q
cp $H/inventory.ini $H/ansible.cfg .; mkdir group_vars; cp $H/group_vars/all.yml group_vars/
c(){ GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git commit -q -m "$2"; }
cp $H/hook/web.lesson1.yml web.yml; git add -A; c "2026-09-22T11:05:00+05:30" "Add web.yml: nginx on the web servers"
S=$H/hook/site.yml
git rm -q web.yml; sed -n '1,/^- name: App settings/p' $S | head -n -1 > site.yml; git add -A
c "2026-09-29T16:40:00+05:30" "Grow web.yml into site.yml: base setup, users, sshd, web-02"
sed -n '1,/^- name: Health-check toolkit/p' $S | head -n -1 > site.yml; git add -A
c "2026-10-06T19:12:00+05:30" "Add app settings for the web servers"
cp $S site.yml; cp -r $H/hook/files .; git add -A
c "2026-10-14T10:30:00+05:30" "Roll out the hc toolkit to every server"
git log --oneline
