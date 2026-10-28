# git-team: the team's lab machine for the Git lessons. Ubuntu 24.04 with Git from Ubuntu's own packages (2.43.0),
# tzdata (the team is in India, +05:30), nano (the editor Git opens) and python3 (the hc toolkit's tests).
# Three accounts stand in for three laptops: asha, priya, rahul, all in group dev, which owns the bare
# "origin" repository under /srv/git (standing in for GitHub).
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive TZ=Asia/Kolkata
RUN apt-get update && apt-get install -y --no-install-recommends git tree tzdata less nano python3 ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime && echo Asia/Kolkata > /etc/timezone \
    && (userdel -r ubuntu 2>/dev/null || true) && groupadd dev \
    && for u in asha priya rahul; do useradd -m -s /bin/bash -G dev $u; done \
    && install -d -g dev -m 2775 /srv/git
CMD ["sleep", "infinity"]
