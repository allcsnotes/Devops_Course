# m06-lab: Ubuntu 24.04 with the tools to look at namespaces and cgroups
#   util-linux (already in Ubuntu): unshare, lsns, nsenter
#   procps: ps    iproute2: ip    psmisc: pstree
#   python3 (3.12): the "dev box" from the opening story
# Users asha and priya exist so you can try the user-namespace demo as a normal user.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends procps iproute2 python3 psmisc less \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && userdel -r ubuntu 2>/dev/null; useradd -m -s /bin/bash asha; useradd -m -s /bin/bash priya
CMD ["sleep", "infinity"]
