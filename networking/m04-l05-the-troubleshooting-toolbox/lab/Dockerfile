# toolbox-lab: Ubuntu 24.04 with every tool of the troubleshooting toolbox, installed with apt:
# curl, dig (bind9-dnsutils), ping + tracepath (iputils), traceroute, mtr (mtr-tiny), ss + ip + tc (iproute2),
# nc (netcat-openbsd), tcpdump, openssl, iptables; plus the lab's servers: BIND 9 (lab DNS), nginx (reverse proxy)
# and python3 (web / API stand-ins). User "asha" can use sudo.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl bind9 bind9-utils bind9-dnsutils iputils-ping iputils-tracepath traceroute mtr-tiny iproute2 \
      netcat-openbsd tcpdump openssl iptables nginx python3 sudo less procps ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && (userdel -r ubuntu 2>/dev/null; true) && useradd -m -s /bin/bash asha \
    && echo 'asha ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/asha && chmod 440 /etc/sudoers.d/asha \
    && install -d -o bind -g bind /var/log/named
CMD ["sleep", "infinity"]
