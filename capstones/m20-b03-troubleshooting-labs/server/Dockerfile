# trouble-server: Ubuntu 24.04 with systemd as PID 1 (web-01 and ns1 behave like real servers).
# web-01: nginx (TLS on 443) in front of the allcsvideos API (python3 + psycopg2, a systemd service).
# ns1: BIND 9, authoritative for allcsvideos.test (the internal names the servers use).
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
LABEL course=devops
RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus procps psmisc sudo tmux less nano curl ca-certificates openssl iproute2 lsof \
      nginx python3 python3-psycopg2 postgresql-client bind9 bind9-utils bind9-dnsutils logrotate \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && (userdel -r ubuntu 2>/dev/null; true) && useradd -m -s /bin/bash asha \
    && echo 'asha ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/asha && chmod 440 /etc/sudoers.d/asha \
    && systemctl disable named nginx >/dev/null 2>&1; true
RUN printf 'set -g default-command bash\nset -g history-limit 20000\nset -g status off\n' > /home/asha/.tmux.conf \
    && echo 'export SYSTEMD_PAGER= SYSTEMD_COLORS=0' >> /home/asha/.bashrc && chown asha:asha /home/asha/.tmux.conf
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
