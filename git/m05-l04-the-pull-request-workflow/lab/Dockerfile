# git-team (M05-L04): the team's lab machine for the pull-request lesson. Ubuntu 24.04 with Git from Ubuntu's own packages,
# tzdata (the team is in India, +05:30), nano, python3 (the hc tests call it), curl and jq (to talk to the Gitea REST API),
# openssh-client (ssh-keygen, for SSH-signed tags), and tea, Gitea's official command-line client, copied from the
# pinned gitea/tea image. Three accounts stand in for three laptops: asha, priya, rahul; "ci" runs the lab CI.
FROM gitea/tea:0.16.0 AS tea
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive TZ=Asia/Kolkata
RUN apt-get update && apt-get install -y --no-install-recommends git tree tzdata less nano python3 curl jq openssh-client ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime && echo Asia/Kolkata > /etc/timezone \
    && (userdel -r ubuntu 2>/dev/null || true) && groupadd dev \
    && for u in asha priya rahul; do useradd -m -s /bin/bash -G dev $u; done && useradd -m -s /bin/bash ci \
    && install -d -g dev -m 2775 /srv/git
COPY --from=tea /usr/bin/tea /usr/local/bin/tea
CMD ["sleep", "infinity"]
