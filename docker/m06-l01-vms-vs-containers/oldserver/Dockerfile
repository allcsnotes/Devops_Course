# m06-oldserver: plays "web-01", the old server from the opening story.
# Ubuntu 22.04 ships its own python3 package: Python 3.10.
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends python3 \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash asha
CMD ["sleep", "infinity"]
