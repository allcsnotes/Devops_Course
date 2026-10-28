# web01-systemd: Ubuntu 24.04 with systemd as PID 1 (recipe from M02-L03), plus cron and logrotate,
# which a full Ubuntu server install already has. web-01 behaves like a real server.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus procps psmisc sudo tmux nginx python3 curl cron logrotate tzdata less nano \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
