# lab-laptop: the team's machine for this lab. Users asha, priya and rahul stand in for three laptops.
#  - terraform 1.16.6, copied from the official hashicorp/terraform:1.16.6 image (no download)
#  - kustomize v5.8.3, the standalone release, sha256-checked
#  - tea 0.16.0 (the Gitea command-line tool), copied from the official gitea/tea:0.16.0 image
FROM hashicorp/terraform:1.16.6 AS tf
FROM gitea/tea:0.16.0 AS tea
FROM ubuntu:24.04
ARG TARGETARCH
ARG KUSTOMIZE_VERSION=v5.8.3
ARG KUSTOMIZE_SHA_arm64=9867b76482cfc6d25b546abc1d2b5a32bd137505aba640649b4b378f64f6d68f
ARG KUSTOMIZE_SHA_amd64=cb9e31198d3f63b44848bd0afc4c8efc56e6cfef9c93a4a39a211940e6decd61
ENV DEBIAN_FRONTEND=noninteractive TZ=Asia/Kolkata
LABEL course=devops
RUN apt-get update && apt-get install -y --no-install-recommends git tree tzdata less curl jq ca-certificates diffutils \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime && echo Asia/Kolkata > /etc/timezone \
    && (userdel -r ubuntu 2>/dev/null || true) && groupadd dev \
    && for u in asha priya rahul; do useradd -m -s /bin/bash -G dev $u; done \
    && mkdir -p /srv/tfstate && chgrp dev /srv/tfstate && chmod 2775 /srv/tfstate \
    && curl -fsSLo /tmp/kz.tgz https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_${TARGETARCH}.tar.gz \
    && if [ "$TARGETARCH" = arm64 ]; then ZS=$KUSTOMIZE_SHA_arm64; else ZS=$KUSTOMIZE_SHA_amd64; fi \
    && echo "$ZS  /tmp/kz.tgz" | sha256sum -c - && tar -xzf /tmp/kz.tgz -C /usr/local/bin kustomize && rm /tmp/kz.tgz
COPY --from=tf /bin/terraform /usr/local/bin/terraform
COPY --from=tea /usr/bin/tea /usr/local/bin/tea
COPY lab-login /usr/local/bin/lab-login.sh
RUN for u in asha priya rahul; do printf 'export PS1="\\u@laptop:\\w\\$ "\nlab-login(){ . /usr/local/bin/lab-login.sh "$@"; }\n' >> /home/$u/.bashrc; done
CMD ["sleep", "infinity"]
