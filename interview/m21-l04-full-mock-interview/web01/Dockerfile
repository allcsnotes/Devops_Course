# web-01: Ubuntu 24.04 with systemd as PID 1 (round 1 of the mock interview), like M02-L03's server.
# Staged on purpose (by web01/up.sh, after boot): Priya's temporary preview server (old-preview.service) holds port 80 while nginx is stopped.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus procps sudo tmux nginx python3 curl dnsutils iproute2 openssl ca-certificates less tzdata \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
# users: asha (on-call, sudo without a password in this lab only) and priya (owns the preview)
RUN ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime && echo Asia/Kolkata > /etc/timezone \
 && useradd -m -s /bin/bash asha && useradd -m -s /bin/bash priya \
 && echo 'asha ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/asha-lab && chmod 0440 /etc/sudoers.d/asha-lab \
 && echo 'export SYSTEMD_PAGER=' >> /home/asha/.bashrc \
 && printf 'set -g default-shell /bin/bash\nset -g history-limit 20000\nset -g status off\n' > /home/asha/.tmux.conf && chown asha: /home/asha/.tmux.conf
COPY old-preview.service /etc/systemd/system/old-preview.service
COPY shop.conf /etc/nginx/sites-available/shop
RUN mkdir -p /srv/preview && echo 'preview build 0.3 (Priya)' > /srv/preview/index.html \
 && ln -s /etc/nginx/sites-available/shop /etc/nginx/sites-enabled/shop \
 && systemctl enable old-preview.service nginx.service
# a lab CA and a certificate for shop.allcs.test (lab-only keys, made at build time)
RUN mkdir -p /etc/ssl/lab && cd /etc/ssl/lab \
 && openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj '/CN=allcs lab CA' -keyout ca.key -out ca.crt 2>/dev/null \
 && openssl req -newkey rsa:2048 -nodes -subj '/CN=shop.allcs.test' -keyout shop.key -out shop.csr 2>/dev/null \
 && printf 'subjectAltName=DNS:shop.allcs.test\n' > san.ext \
 && openssl x509 -req -in shop.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 30 -extfile san.ext -out shop.crt 2>/dev/null \
 && cp ca.crt /home/asha/lab-ca.crt && chown asha: /home/asha/lab-ca.crt
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
