# dnslab: Ubuntu 24.04 with BIND 9 (the DNS server), the dig / host / nslookup clients (bind9-dnsutils),
# curl, python3 (a tiny web server for the API stand-ins) and nano. Installed with apt.
# User "asha" can use sudo without a password.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      bind9 bind9-utils bind9-dnsutils curl python3 sudo less procps iproute2 ca-certificates nano \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && (userdel -r ubuntu 2>/dev/null || true) && useradd -m -s /bin/bash asha \
    && echo 'asha ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/asha && chmod 440 /etc/sudoers.d/asha \
    && install -d -o bind -g bind /var/log/named
WORKDIR /home/asha
CMD ["sleep", "infinity"]
