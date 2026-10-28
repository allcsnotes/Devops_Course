# ssh-lab-sshd: Ubuntu 24.04 with systemd as PID 1 and a real OpenSSH server (used for the bastion and web-01).
# The two "laptops" use the same image without systemd: they only need the ssh client side.
# Host keys are regenerated per server by setup-server.sh, so every server gets its own fingerprint.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus openssh-server openssh-client sudo rsync python3 nano less procps iproute2 \
      postgresql-client ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
