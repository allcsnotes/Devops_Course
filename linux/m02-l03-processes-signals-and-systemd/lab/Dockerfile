# web-01 for M02-L03: Ubuntu 24.04 with systemd as PID 1, so it behaves like a real server.
#   Build: docker build -t linux-lab:m02-l03 lab/
#   Run:   docker run -d --rm --name linux-lab --hostname web-01 --privileged --cgroupns=private \
#            --tmpfs /run --tmpfs /run/lock linux-lab:m02-l03
#   Shell: docker exec -it linux-lab su - asha
# Recorded with systemd 255.4-1ubuntu8.18, procps 4.0.4, psmisc 23.7, nginx 1.24.0, Python 3.12.3,
# sudo 1.9.15p5, tmux 3.4 (apt may give newer patch releases).
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus procps psmisc sudo tmux nginx python3 curl cron less nano \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Lesson files: the API stand-in, the demo upload worker, the zombie demo
COPY files/ /tmp/files/
COPY setup-root.sh /usr/local/sbin/
RUN bash /usr/local/sbin/setup-root.sh && rm -rf /tmp/files

# systemd stops cleanly on SIGRTMIN+3
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
