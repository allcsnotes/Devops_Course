# ports-lab: Ubuntu 24.04 with the networking tools this lesson uses, installed with apt:
# iproute2 (ip, ss), ufw, iptables, nftables, netcat-openbsd (nc), curl, tcpdump, nginx (web server),
# openssh (bastion -> web-01) and python3 (the Course Copilot stand-in). User "asha" can use sudo.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      iproute2 iputils-ping ufw iptables nftables netcat-openbsd curl tcpdump nginx \
      openssh-server openssh-client sudo python3 less procps ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && (userdel -r ubuntu 2>/dev/null; true) && useradd -m -s /bin/bash asha \
    && echo 'asha ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/asha && chmod 440 /etc/sudoers.d/asha \
    && mkdir -p /run/sshd
CMD ["sleep", "infinity"]
