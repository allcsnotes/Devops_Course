# trouble-ops: Asha's ops workstation. docker CLI + kind + kubectl (pinned, checksum-verified, from the M13/M14 lab),
# plus curl, dig, openssl, psql, git, tmux, and the real gitleaks 8.30.1 binary from its official image.
FROM zricethezav/gitleaks:v8.30.1 AS gitleaks
FROM docker:29.5.3-cli
ARG TARGETARCH
ARG KIND_VERSION=v0.33.0
ARG KUBECTL_VERSION=v1.37.1
ARG KIND_SHA_arm64=20022bee6cfcd5086cb7234d218e3454e6090022f2a8f55d1fa7fcf42c3867a2
ARG KIND_SHA_amd64=aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d
ARG KUBECTL_SHA_arm64=ff749f4b78d9c4f1ec87307df9b50119ed819e2094aa9810cb9acffc3286c8c7
ARG KUBECTL_SHA_amd64=65691ff77eb6fa44c908b77a1082c9f092c3b9733b5cefabec0d1104890e21a8
LABEL course=devops
RUN apk add --no-cache bash tmux curl bind-tools openssl git postgresql-client ca-certificates jq ncurses less \
 && curl -fsSLo /usr/local/bin/kind https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${TARGETARCH} \
 && curl -fsSLo /usr/local/bin/kubectl https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl \
 && if [ "$TARGETARCH" = arm64 ]; then KS=$KIND_SHA_arm64; CS=$KUBECTL_SHA_arm64; else KS=$KIND_SHA_amd64; CS=$KUBECTL_SHA_amd64; fi \
 && echo "$KS  /usr/local/bin/kind" | sha256sum -c - \
 && echo "$CS  /usr/local/bin/kubectl" | sha256sum -c - \
 && chmod +x /usr/local/bin/kind /usr/local/bin/kubectl \
 && adduser -D -s /bin/bash -u 1000 asha && addgroup asha root
COPY --from=gitleaks /usr/bin/gitleaks /usr/local/bin/gitleaks
# lab clocks run in UTC, like the servers (alpine has no tzdata: POSIX TZ string)
ENV TZ=UTC
USER asha
WORKDIR /home/asha
RUN echo 'export PS1="\u@\h:\w\$ "' >> /home/asha/.bashrc \
 && printf 'set -g default-shell /bin/bash\nset -g default-command bash\nset -g history-limit 20000\nset -g status off\n' > /home/asha/.tmux.conf \
 && git config --global user.name Asha && git config --global user.email asha@example.com \
 && git config --global init.defaultBranch main && git config --global core.pager cat
CMD ["sleep", "infinity"]
