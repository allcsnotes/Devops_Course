#!/bin/bash
# Runs when the lab container starts (as root). /data is a small in-memory disk (tmpfs) given by `docker run --tmpfs`,
# so it starts empty every time: prepare it, start nginx, then keep the container alive.
set -e
if [[ -d /data ]]; then
  chown asha:asha /data && chmod 755 /data
  install -d -o asha -g asha /data/uploads
  fallocate -l 9M /data/uploads/lesson-05.mp4             # Meera's upload from M02-L05 (a placeholder file)
  chown asha:asha /data/uploads/lesson-05.mp4
fi
nginx                                                      # starts the nginx daemon (there is no systemd in this lab server)
exec sleep infinity
