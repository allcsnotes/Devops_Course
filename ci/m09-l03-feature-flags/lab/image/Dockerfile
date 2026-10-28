# web-01 image: the server web-01 where flagd's flag file lives (/etc/flagd, kept in a local Git repository so every
# change has an author and a message). Ubuntu 24.04 + curl, jq, git, python3 (the rollout check), nano (to edit the
# flag file).
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive TZ=Asia/Kolkata
RUN apt-get update && apt-get install -y --no-install-recommends curl jq git python3 nano less ca-certificates tzdata \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime && echo Asia/Kolkata > /etc/timezone \
    && (userdel -r ubuntu 2>/dev/null || true) && useradd -m -s /bin/bash -u 1000 asha
CMD ["sleep", "infinity"]
