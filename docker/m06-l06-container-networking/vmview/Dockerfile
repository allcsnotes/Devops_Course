# VM-view lab shell (as in M06-L01): Ubuntu 24.04 + iproute2 (ip, bridge) and iptables. Run it privileged with the
# Docker host's PID, UTS and network namespaces to look at Docker Desktop's VM (or a Linux host) from the inside:
#   docker run -it --rm --privileged --net=host --pid=host --uts=host allcs/vmview:1.0
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends iproute2 iptables nftables procps \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
CMD ["bash"]
