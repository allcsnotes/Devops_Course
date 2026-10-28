# hc-lab-web01: Ubuntu 24.04 with systemd as PID 1 (the recipe from M02-L03),
# plus the packages a web-01 server has: nginx, python3, logrotate, sudo.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus procps sudo tmux nginx python3 curl logrotate cron tzdata less util-linux \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
