# securepipe-lab: the team's lab machine (one container stands in for three laptops: asha, priya, rahul).
# From the M18-L04 tool box (docker CLI + kind + kubectl + Helm + cosign, every binary pinned and checksum-verified,
# checked 2026-10-21) plus Git and gitleaks for the pre-commit hook (M18-L01).
#   kind v0.33.0 · kubectl v1.35.9 (cluster kindest/node v1.35.8: Kyverno 1.19 supports Kubernetes 1.33-1.35)
#   Helm v4.3.1 · cosign v3.1.4 · gitleaks 8.30.1 (copied unchanged from zricethezav/gitleaks:v8.30.1)
#   uv 0.13.4 (copied from ghcr.io/astral-sh/uv:0.13.4, as in M18-L03) + python3, for the locked requirements
FROM zricethezav/gitleaks:v8.30.1 AS gitleaks
FROM ghcr.io/astral-sh/uv:0.13.4 AS uv
FROM docker:29.5.3-cli
ARG TARGETARCH
ARG KIND_VERSION=v0.33.0
ARG KUBECTL_VERSION=v1.35.9
ARG HELM_VERSION=v4.3.1
ARG COSIGN_VERSION=v3.1.4
ARG KIND_SHA_arm64=20022bee6cfcd5086cb7234d218e3454e6090022f2a8f55d1fa7fcf42c3867a2
ARG KIND_SHA_amd64=aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d
ARG KUBECTL_SHA_arm64=39c98bca82875d9a9ddfb6f3c5ab17c3f78ea0801230683e538a67d5c053308d
ARG KUBECTL_SHA_amd64=3cfeaf80be482b435b0aa214aff6e0b2c312ee23c0ff20810c75517b6004c6eb
ARG HELM_SHA_arm64=8cf8f66ecbc252ac8f7f06cca68aba88508ddfde3a6a34feb1678ad1694b4f88
ARG HELM_SHA_amd64=0403a88ae20913d11b10a2467b50087721fea7581736da6b9d3992f5357fe54b
ARG COSIGN_SHA_arm64=ade83b7aac62e131cacfe96d958948b2150cc9efec46a570a2649b8e27dedad2
ARG COSIGN_SHA_amd64=424e2c97d0b45fd7a6b608a87f090f35633f4c23ece5f092d48bba11aaf4bbfa
LABEL course=devops
RUN apk add --no-cache bash tmux curl jq git ncurses tree tzdata python3 \
 && if [ "$TARGETARCH" = arm64 ]; then KS=$KIND_SHA_arm64; CS=$KUBECTL_SHA_arm64; HS=$HELM_SHA_arm64; OS=$COSIGN_SHA_arm64; \
    else KS=$KIND_SHA_amd64; CS=$KUBECTL_SHA_amd64; HS=$HELM_SHA_amd64; OS=$COSIGN_SHA_amd64; fi \
 && curl -fsSLo /usr/local/bin/kind https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${TARGETARCH} \
 && curl -fsSLo /usr/local/bin/kubectl https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl \
 && curl -fsSLo /usr/local/bin/cosign https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-${TARGETARCH} \
 && curl -fsSLo /tmp/helm.tgz https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz \
 && echo "$KS  /usr/local/bin/kind" | sha256sum -c - \
 && echo "$CS  /usr/local/bin/kubectl" | sha256sum -c - \
 && echo "$OS  /usr/local/bin/cosign" | sha256sum -c - \
 && echo "$HS  /tmp/helm.tgz" | sha256sum -c - \
 && tar -xzf /tmp/helm.tgz -C /tmp && mv /tmp/linux-${TARGETARCH}/helm /usr/local/bin/helm \
 && rm -rf /tmp/* && chmod +x /usr/local/bin/kind /usr/local/bin/kubectl /usr/local/bin/cosign /usr/local/bin/helm \
 && cp /usr/share/zoneinfo/Asia/Kolkata /etc/localtime && echo Asia/Kolkata > /etc/timezone \
 && for u in asha priya rahul; do adduser -D -s /bin/bash $u && addgroup $u root; done
COPY --from=gitleaks /usr/bin/gitleaks /usr/local/bin/gitleaks
COPY --from=uv /uv /usr/local/bin/uv
# the Docker Desktop socket is root:root 0660 inside containers, so the users join group root (gid 0) to use it
RUN for u in asha priya rahul; do \
      echo 'export PS1="\u@\h:\w\$ "' >> /home/$u/.bashrc; \
      printf 'set -g default-shell /bin/bash\nset -g default-command bash\nset -g history-limit 20000\nset -g status off\n' > /home/$u/.tmux.conf; \
      chown $u:$u /home/$u/.bashrc /home/$u/.tmux.conf; done
CMD ["sleep", "infinity"]
