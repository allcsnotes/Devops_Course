# mig-ops: Asha's operations box for the migration (hostname ops, user asha).
# docker CLI 29.5.3 + kind v0.33.0 + kubectl v1.36.4 + Helm v4.3.1 (all sha256-checked) + Ansible (ansible-core 2.21.5 in a
# venv, the M12 control node) + the PostgreSQL 18 client tools (backups before the cutover) + tmux.
# kind talks to Docker Desktop through the mounted socket; the kind node and the VMs are containers on the lab network.
FROM docker:29.5.3-cli
ARG TARGETARCH
ARG KIND_VERSION=v0.33.0
ARG KUBECTL_VERSION=v1.36.4
ARG HELM_VERSION=v4.3.1
ARG KIND_SHA_arm64=20022bee6cfcd5086cb7234d218e3454e6090022f2a8f55d1fa7fcf42c3867a2
ARG KIND_SHA_amd64=aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d
# get.helm.sh/helm-v4.3.1-linux-<arch>.tar.gz.sha256sum (release 2026-10-15)
ARG HELM_SHA_arm64=8cf8f66ecbc252ac8f7f06cca68aba88508ddfde3a6a34feb1678ad1694b4f88
ARG HELM_SHA_amd64=0403a88ae20913d11b10a2467b50087721fea7581736da6b9d3992f5357fe54b
LABEL course=devops
ENV TZ=UTC
RUN apk add --no-cache bash bash-completion tmux curl jq git tree tzdata coreutils diffutils openssh-client python3 py3-pip postgresql18-client \
 && curl --http1.1 --retry 5 --retry-all-errors -fsSLo /usr/local/bin/kind https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${TARGETARCH} \
 && if [ "$TARGETARCH" = arm64 ]; then KS=$KIND_SHA_arm64; HS=$HELM_SHA_arm64; else KS=$KIND_SHA_amd64; HS=$HELM_SHA_amd64; fi \
 && echo "$KS  /usr/local/bin/kind" | sha256sum -c - \
 && curl --http1.1 --retry 5 --retry-all-errors -fsSLo /usr/local/bin/kubectl https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl \
 && curl --http1.1 --retry 5 --retry-all-errors -fsSLo /tmp/kubectl.sha256 https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256 \
 && echo "$(cat /tmp/kubectl.sha256)  /usr/local/bin/kubectl" | sha256sum -c - && rm /tmp/kubectl.sha256 \
 && curl --http1.1 --retry 5 --retry-all-errors -fsSLo /tmp/helm.tgz https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz \
 && echo "$HS  /tmp/helm.tgz" | sha256sum -c - && tar -xzf /tmp/helm.tgz -C /tmp && mv /tmp/linux-${TARGETARCH}/helm /usr/local/bin/helm && rm -rf /tmp/helm.tgz /tmp/linux-* \
 && chmod +x /usr/local/bin/kind /usr/local/bin/kubectl /usr/local/bin/helm \
 && adduser -D -s /bin/bash -u 1000 asha && addgroup asha root
# the Docker Desktop socket is root:root 0660 inside containers, so asha joins group root (gid 0) to use it
USER asha
WORKDIR /home/asha
RUN python3 -m venv /home/asha/.venvs/ansible && /home/asha/.venvs/ansible/bin/pip install -q ansible-core==2.21.5 \
 && echo 'export PATH=$HOME/.venvs/ansible/bin:$HOME/bin:$PATH' >> /home/asha/.bashrc \
 && echo 'source <(kubectl completion bash)' >> /home/asha/.bashrc \
 && printf 'set -g default-shell /bin/bash\nset -g default-command bash\nset -g history-limit 20000\nset -g status off\n' > /home/asha/.tmux.conf
CMD ["sleep", "infinity"]
