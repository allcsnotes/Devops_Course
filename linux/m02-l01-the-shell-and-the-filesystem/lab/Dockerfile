# web-01 for M02-L01: the same Ubuntu 24.04 server the lesson was recorded on.
#   Build: docker build -t linux-lab:m02-l01 lab/
#   Run:   docker run -it --rm --name linux-lab --hostname web-01 linux-lab:m02-l01
FROM ubuntu:24.04
ARG DEBIAN_FRONTEND=noninteractive

# The ubuntu:24.04 image is "minimized": no man pages. unminimize brings them back (the lesson shows both).
RUN apt-get update \
    && apt-get install -y unminimize \
    && yes | unminimize

# The tools the lesson uses. Recorded with nginx 1.24.0-2ubuntu7.18 (apt may give a newer patch release).
RUN apt-get install -y nginx man-db file less tmux curl

# User asha, the allcsvideos site files, and the site config (written to sites-available, NOT enabled on purpose).
COPY site/ /tmp/site/
COPY setup-root.sh start.sh /usr/local/sbin/
RUN bash /usr/local/sbin/setup-root.sh && rm -rf /tmp/site

# Starts nginx as root, then gives you a login shell as asha.
CMD ["bash", "/usr/local/sbin/start.sh"]
