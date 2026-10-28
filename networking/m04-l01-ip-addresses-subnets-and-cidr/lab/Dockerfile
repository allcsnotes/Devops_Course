# lab-net: Ubuntu 24.04 with the networking tools this lesson uses, installed with apt:
# iproute2 (ip), ipcalc, ping, traceroute, tracepath, python3. User "asha" can use sudo without a password.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      iproute2 ipcalc iputils-ping iputils-tracepath traceroute sudo python3 less procps \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && (userdel -r ubuntu 2>/dev/null || true) && useradd -m -s /bin/bash asha \
    && echo 'asha ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/asha && chmod 440 /etc/sudoers.d/asha
WORKDIR /home/asha
CMD ["sleep", "infinity"]
