# tls-lab: Ubuntu 24.04 with what this lesson uses, installed with apt:
# nginx 1.24 (reverse proxy), openssl 3.0, curl 8.5, tcpdump, certbot 2.9 (ACME client), python3 (app stand-ins),
# dnsutils (dig), iproute2, sudo. Users: asha (sudo) and lukas (sudo, for the trust-store step).
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      nginx openssl curl tcpdump certbot python3 dnsutils iproute2 iputils-ping sudo less procps ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && (userdel -r ubuntu 2>/dev/null; true) && useradd -m -s /bin/bash asha && useradd -m -s /bin/bash lukas \
    && echo 'asha ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/asha && chmod 440 /etc/sudoers.d/asha \
    && echo 'lukas ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/lukas && chmod 440 /etc/sudoers.d/lukas
CMD ["sleep", "infinity"]
