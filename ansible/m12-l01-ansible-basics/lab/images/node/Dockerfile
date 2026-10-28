# A managed node. Ubuntu 24.04 with systemd as PID 1 (recipe from M02-L03) and a real OpenSSH server
# (recipe from M02-L06). python3 is there because Ansible modules are Python programs that run on the target.
# No nginx: the lesson installs it with Ansible. apt lists are removed, like a fresh cloud image (update_cache needed).
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus openssh-server sudo python3 iproute2 procps less nano curl ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
