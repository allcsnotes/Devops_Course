#!/bin/sh
# Starts the environment host: SSH server, the read-only deployment record on :8080, then its Docker engine (PID 1 path
# of the official docker:dind image).
set -e
ssh-keygen -A >/dev/null                      # this host's own SSH host keys (new per host)
: "${IMAGE_REPO:?set IMAGE_REPO, e.g. ghcr.io/<owner>/course-copilot}"
printf 'REPO=%s\n' "$IMAGE_REPO" > /etc/deploy-agent.conf && chmod 644 /etc/deploy-agent.conf
/usr/sbin/sshd -E /var/log/sshd.log
su deploy -s /bin/sh -c 'cd /srv/deploys && exec python3 -m http.server 8080 >/dev/null 2>&1' &
exec dockerd-entrypoint.sh "$@"
