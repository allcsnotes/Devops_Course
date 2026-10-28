# lab-agent: LAB STAND-IN for Argo CD in each "account". A small loop that pulls the deploy repo
# (read-only token), renders ONE overlay with kustomize, and runs exactly what it says (image digest,
# replicas, config) as containers named lab-<env>-api-<n>. Pull-based, like module 15's GitOps.
# The same image (with the Docker CLI and buildx) is also the CI build box, build-01.
FROM docker:29.5.3-cli
ARG TARGETARCH
ARG KUSTOMIZE_VERSION=v5.8.3
ARG KUSTOMIZE_SHA_arm64=9867b76482cfc6d25b546abc1d2b5a32bd137505aba640649b4b378f64f6d68f
ARG KUSTOMIZE_SHA_amd64=cb9e31198d3f63b44848bd0afc4c8efc56e6cfef9c93a4a39a211940e6decd61
LABEL course=devops
RUN apk add --no-cache bash git curl jq \
 && curl -fsSLo /tmp/kz.tgz https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_${TARGETARCH}.tar.gz \
 && if [ "$TARGETARCH" = arm64 ]; then ZS=$KUSTOMIZE_SHA_arm64; else ZS=$KUSTOMIZE_SHA_amd64; fi \
 && echo "$ZS  /tmp/kz.tgz" | sha256sum -c - && tar -xzf /tmp/kz.tgz -C /usr/local/bin kustomize && rm /tmp/kz.tgz
COPY agent.sh /agent.sh
COPY build-image.sh /usr/local/bin/build-image
RUN chmod +x /usr/local/bin/build-image
ENV TZ=IST-5:30
CMD ["bash", "/agent.sh"]
