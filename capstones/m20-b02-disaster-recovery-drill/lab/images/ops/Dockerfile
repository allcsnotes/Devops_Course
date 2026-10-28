# Asha's ops laptop for the M20-B02 drill: docker CLI + kind v0.33.0 + kubectl v1.36.4 (checksum-verified, as in M15-L03)
# + Terraform 1.16.6 + the Vault 2.1.2 CLI (copied from the official images) + psql 18.6 + git, jq, tmux, python3.
# It sits OUTSIDE the production environment, like a real laptop: the disaster never touches it.
FROM hashicorp/terraform:1.16.6 AS tf
FROM hashicorp/vault:2.1.2 AS vault
FROM docker:29.5.3-cli
ARG TARGETARCH
ARG KIND_VERSION=v0.33.0
ARG KUBECTL_VERSION=v1.36.4
ARG KIND_SHA_arm64=20022bee6cfcd5086cb7234d218e3454e6090022f2a8f55d1fa7fcf42c3867a2
ARG KIND_SHA_amd64=aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d
LABEL course=devops
ENV TZ=UTC
RUN apk add --no-cache bash tmux curl jq git tzdata ncurses coreutils postgresql18-client python3 gawk \
 && curl --http1.1 --retry 5 --retry-all-errors -fsSLo /usr/local/bin/kind https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${TARGETARCH} \
 && if [ "$TARGETARCH" = arm64 ]; then KS=$KIND_SHA_arm64; else KS=$KIND_SHA_amd64; fi \
 && echo "$KS  /usr/local/bin/kind" | sha256sum -c - \
 && curl --http1.1 --retry 5 --retry-all-errors -fsSLo /usr/local/bin/kubectl https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl \
 && curl --http1.1 --retry 5 --retry-all-errors -fsSLo /tmp/kubectl.sha256 https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256 \
 && echo "$(cat /tmp/kubectl.sha256)  /usr/local/bin/kubectl" | sha256sum -c - && rm /tmp/kubectl.sha256 \
 && chmod +x /usr/local/bin/kind /usr/local/bin/kubectl \
 && adduser -D -s /bin/bash -u 1000 asha && addgroup asha root \
 && adduser -D -s /bin/bash -u 1001 rahul && addgroup rahul root
COPY --from=tf /bin/terraform /usr/local/bin/terraform
COPY --from=vault /bin/vault /usr/local/bin/vault
# the Docker Desktop socket is root:root 0660 inside containers, so asha joins group root (gid 0) to use it
USER asha
WORKDIR /home/asha
RUN echo 'export PS1="\u@\h:\w\$ "' >> .bashrc \
 && echo 'export VAULT_ADDR=http://10.0.202.11:8200 KUBECONFIG=/home/asha/.kube/config' >> .bashrc \
 && printf 'set -g default-shell /bin/bash\nset -g default-command bash\nset -g history-limit 50000\nset -g status off\n' > .tmux.conf
USER root
RUN cp /home/asha/.bashrc /home/asha/.tmux.conf /home/rahul/ && chown rahul:rahul /home/rahul/.bashrc /home/rahul/.tmux.conf
USER asha
CMD ["sleep", "infinity"]
