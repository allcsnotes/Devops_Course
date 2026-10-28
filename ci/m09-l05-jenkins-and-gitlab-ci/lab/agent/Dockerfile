# The lab build agent: the official inbound agent (Java + the agent jar + git) plus the Docker CLI and buildx.
# Its Docker CLI talks to the lab's own Docker-in-Docker daemon (tcp://docker:2376, TLS), never to the Mac's Docker.
FROM jenkins/inbound-agent:3391.va_37fa_a_305d6d-5-jdk21
COPY --from=docker:29.5.3-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker:29.5.3-cli /usr/local/libexec/docker/cli-plugins/docker-buildx /usr/local/libexec/docker/cli-plugins/docker-buildx
ENV DOCKER_HOST=tcp://docker:2376 DOCKER_TLS_VERIFY=1 DOCKER_CERT_PATH=/certs/client
