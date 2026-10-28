# The "web-01" server from the video: Ubuntu 24.04, the allcsvideos API stand-in, and an older nginx for the apt demos.
# The small data disk (/data) is NOT part of the image: up.sh mounts a 64 MB tmpfs there when the container starts,
# and start.sh fills it. Build and start with ./up.sh, remove with ./down.sh.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# tools the lesson uses, plus nginx pinned to the noble release version, so an update is waiting for the hold demo
RUN apt-get update -qq \
 && apt-get install -y -qq sudo python3 curl lsof less nano >/dev/null \
 && apt-get install -y -qq nginx=1.24.0-2ubuntu7 nginx-common=1.24.0-2ubuntu7 >/dev/null

# users: asha (sudo + adm) and allcs, the API's own system user from lesson 3
RUN useradd -m -s /bin/bash -G sudo,adm asha \
 && echo 'asha:demo-password-123' | chpasswd \
 && useradd --system --no-create-home -s /usr/sbin/nologin allcs
# ^ FAKE demo password for this throwaway lab only. sudo asks for it.

# the API stand-in and its settings (debug logging left on: that is the bug)
COPY files/api.py /opt/allcsvideos/api.py
COPY files/gen_fill.py /root/gen_fill.py
COPY files/data.fstab /home/asha/data.fstab
COPY start.sh /usr/local/sbin/start.sh
RUN chmod 755 /opt/allcsvideos/api.py /usr/local/sbin/start.sh \
 && chown asha:asha /home/asha/data.fstab \
 && install -d -m 755 /srv/allcsvideos \
 && printf '%s\n' '# allcsvideos API settings' 'APP_ENV=production' \
      '# Priya, 19 Oct: debug on to chase the cache bug' 'LOG_LEVEL=debug' \
      'LOG_DIR=/data/logs' 'UPLOAD_DIR=/data/uploads' > /srv/allcsvideos/app.env \
 && chmod 644 /srv/allcsvideos/app.env

# Meera's new lesson (6 MB of random bytes), waiting to be uploaded
RUN head -c 6291456 /dev/urandom > /tmp/lesson-05.mp4 && chmod 644 /tmp/lesson-05.mp4

# empty the package lists: the state a fresh Ubuntu image starts in (the lesson runs `apt update` itself)
RUN rm -rf /var/lib/apt/lists/*

CMD ["/usr/local/sbin/start.sh"]
