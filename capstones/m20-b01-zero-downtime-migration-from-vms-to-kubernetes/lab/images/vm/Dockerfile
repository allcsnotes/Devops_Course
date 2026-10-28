# mig-vm: one allcsvideos server from the M12 fleet (M12-B01 node image). Ubuntu 24.04 with systemd as PID 1
# (recipe from M02-L03) and a real OpenSSH server (recipe from M02-L06), standing in for a VM. python3 + venv because
# Ansible modules are Python programs and the catalog API runs from a venv. apt lists removed, like a fresh cloud image.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus openssh-server sudo python3 python3-venv iproute2 procps less curl ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
