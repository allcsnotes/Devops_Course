# Kubernetes lab tool box: docker CLI + kind + kubectl, pinned and checksum-verified.
# kind talks to Docker Desktop through the mounted socket; the cluster nodes are Docker containers.
FROM docker:29.5.3-cli
ARG TARGETARCH
ARG KIND_VERSION=v0.33.0
ARG KUBECTL_VERSION=v1.37.1
ARG KIND_SHA_arm64=20022bee6cfcd5086cb7234d218e3454e6090022f2a8f55d1fa7fcf42c3867a2
ARG KIND_SHA_amd64=aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d
ARG KUBECTL_SHA_arm64=ff749f4b78d9c4f1ec87307df9b50119ed819e2094aa9810cb9acffc3286c8c7
ARG KUBECTL_SHA_amd64=65691ff77eb6fa44c908b77a1082c9f092c3b9733b5cefabec0d1104890e21a8
LABEL course=devops
RUN apk add --no-cache bash bash-completion tmux curl moreutils ncurses jq \
 && curl -fsSLo /usr/local/bin/kind https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${TARGETARCH} \
 && curl -fsSLo /usr/local/bin/kubectl https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl \
 && if [ "$TARGETARCH" = arm64 ]; then KS=$KIND_SHA_arm64; CS=$KUBECTL_SHA_arm64; else KS=$KIND_SHA_amd64; CS=$KUBECTL_SHA_amd64; fi \
 && echo "$KS  /usr/local/bin/kind" | sha256sum -c - \
 && echo "$CS  /usr/local/bin/kubectl" | sha256sum -c - \
 && chmod +x /usr/local/bin/kind /usr/local/bin/kubectl \
 && adduser -D -s /bin/bash -u 1000 asha && addgroup asha root \
 && adduser -D -s /bin/bash -u 1001 priya && addgroup priya root
# the Docker Desktop socket is root:root 0660 inside containers, so asha joins group root (gid 0) to use it
USER asha
WORKDIR /home/asha
# (M18-L02 copy: only creates the kind cluster; kubectl/helm run on the lab machine)
RUN echo 'export PS1="\u@\h:\w\$ "' >> /home/asha/.bashrc \
 && echo 'source <(kubectl completion bash)' >> /home/asha/.bashrc \
 && printf 'set -g default-shell /bin/bash\nset -g default-command bash\nset -g history-limit 20000\nset -g status off\n' > /home/asha/.tmux.conf
USER root
RUN cp /home/asha/.bashrc /home/asha/.tmux.conf /home/priya/ && chown priya:priya /home/priya/.bashrc /home/priya/.tmux.conf
USER asha
CMD ["sleep", "infinity"]
