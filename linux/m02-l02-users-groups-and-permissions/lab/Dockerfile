# web-01 for M02-L02: the same Ubuntu 24.04 server the lesson was recorded on.
#   Build: docker build -t linux-lab:m02-l02 lab/
#   Run:   docker run -it --rm --name linux-lab --hostname web-01 linux-lab:m02-l02
FROM ubuntu:24.04
ARG DEBIAN_FRONTEND=noninteractive

# Recorded with sudo 1.9.15p5-3ubuntu5.24.04.4, adduser 3.137ubuntu1, acl 2.3.2, nginx 1.24.0, tmux 3.4, nano 7.2
# (apt may give a newer patch release).
RUN apt-get update \
    && apt-get install -y sudo adduser acl tmux nginx nano \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY setup-root.sh start.sh /usr/local/sbin/
RUN bash /usr/local/sbin/setup-root.sh

# Starts nginx as root, then gives you a real login shell as asha (so Ubuntu's umask applies).
CMD ["bash", "/usr/local/sbin/start.sh"]
