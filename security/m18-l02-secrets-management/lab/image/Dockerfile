# secrets-dev: the team's lab machine for M18-L02 (asha, priya, rahul stand in for three laptops).
# Base python:3.13.16-slim (Debian 13 "trixie"): git-filter-repo is a Python script, installed with pip, pinned.
#   git              Debian's git package
#   git-filter-repo  2.47.0 from PyPI (released 2024-12-04, the version GitHub's docs ask for: --sensitive-data-removal)
#   gitleaks 8.30.1  copied unchanged from the official image zricethezav/gitleaks:v8.30.1 (as in M18-L01)
#   vault 2.1.2      the CLI copied unchanged from the official image hashicorp/vault:2.1.2 (the server runs in its own container)
#   psql             Debian's postgresql-client (to log in with the dynamic database credentials)
#   kubectl v1.37.1 + helm v4.3.1, sha256-checked (same pins as the M13-M15 Kubernetes lab tool box)
# tmux is only used to capture real terminal screens. Every secret in this lab is FAKE or a throwaway lab value.
FROM zricethezav/gitleaks:v8.30.1 AS gitleaks
FROM hashicorp/vault:2.1.2 AS vault
FROM python:3.13.16-slim
ARG TARGETARCH
ARG KUBECTL_VERSION=v1.37.1
ARG HELM_VERSION=v4.3.1
ARG KUBECTL_SHA_arm64=ff749f4b78d9c4f1ec87307df9b50119ed819e2094aa9810cb9acffc3286c8c7
ARG KUBECTL_SHA_amd64=65691ff77eb6fa44c908b77a1082c9f092c3b9733b5cefabec0d1104890e21a8
ARG HELM_SHA_arm64=8cf8f66ecbc252ac8f7f06cca68aba88508ddfde3a6a34feb1678ad1694b4f88
ARG HELM_SHA_amd64=0403a88ae20913d11b10a2467b50087721fea7581736da6b9d3992f5357fe54b
ENV DEBIAN_FRONTEND=noninteractive TZ=Asia/Kolkata
RUN apt-get update && apt-get install -y --no-install-recommends git tmux less curl jq ca-certificates tree tzdata procps postgresql-client \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime && echo Asia/Kolkata > /etc/timezone \
    && groupadd dev && for u in asha priya rahul; do useradd -m -s /bin/bash -G dev $u; done
RUN pip install --no-cache-dir git-filter-repo==2.47.0
RUN if [ "$TARGETARCH" = arm64 ]; then CS=$KUBECTL_SHA_arm64; HS=$HELM_SHA_arm64; else CS=$KUBECTL_SHA_amd64; HS=$HELM_SHA_amd64; fi \
 && curl -fsSLo /usr/local/bin/kubectl https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl \
 && curl -fsSLo /tmp/helm.tgz https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz \
 && echo "$CS  /usr/local/bin/kubectl" | sha256sum -c - && echo "$HS  /tmp/helm.tgz" | sha256sum -c - \
 && tar -xzf /tmp/helm.tgz -C /tmp && mv /tmp/linux-${TARGETARCH}/helm /usr/local/bin/helm && rm -rf /tmp/* && chmod +x /usr/local/bin/kubectl /usr/local/bin/helm
COPY --from=gitleaks /usr/bin/gitleaks /usr/local/bin/gitleaks
COPY --from=vault /bin/vault /usr/local/bin/vault
RUN for u in asha priya rahul; do echo 'export PS1="\u@\h:\w\$ "' >> /home/$u/.bashrc; printf 'set -g default-shell /bin/bash\nset -g default-command bash\nset -g history-limit 20000\nset -g status off\n' > /home/$u/.tmux.conf; chown $u:$u /home/$u/.tmux.conf; done
CMD ["sleep", "infinity"]
