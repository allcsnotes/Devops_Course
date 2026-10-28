# git-laptop: a clean Ubuntu 24.04 "laptop" for the Git lessons, with Git 2.43.0 from Ubuntu's own packages
# (the same `apt install git` as M01-L03), tree (to show the .git folder) and tzdata (Asha is in Mumbai, +05:30).
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive TZ=Asia/Kolkata
RUN apt-get update && apt-get install -y --no-install-recommends git tree tzdata less ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime && echo Asia/Kolkata > /etc/timezone \
    && (userdel -r ubuntu 2>/dev/null; true) && useradd -m -s /bin/bash asha
CMD ["sleep", "infinity"]
