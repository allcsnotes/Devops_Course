# Asha's laptop terminal: git, the Docker CLI (to the lab's Docker-in-Docker daemon) and gitlab-ci-local
FROM node:22.23.3-slim
RUN apt-get update && apt-get install -y --no-install-recommends git rsync curl ca-certificates jq tmux bash \
 && rm -rf /var/lib/apt/lists/*
COPY --from=docker:29.5.3-cli /usr/local/bin/docker /usr/local/bin/docker
RUN npm install -g gitlab-ci-local@4.76.1
RUN useradd -m -s /bin/bash asha
ENV DOCKER_HOST=tcp://docker:2376 DOCKER_TLS_VERIFY=1 DOCKER_CERT_PATH=/certs/client
USER asha
WORKDIR /home/asha
