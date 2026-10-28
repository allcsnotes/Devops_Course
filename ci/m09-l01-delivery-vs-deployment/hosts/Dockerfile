# env-host: one "server" per environment (staging-01, prod-01). Both are built from this ONE file, so the two
# environments are the same machine apart from their name and their app.env (environment parity).
#  - its own Docker engine (docker:29.5.3-dind, privileged as Docker-in-Docker needs) that runs the app with Compose
#  - an SSH server: the pipeline logs in as user "deploy", whose key may ONLY run the deploy agent (forced command)
#  - a tiny read-only HTTP endpoint on port 8080 that serves the deployment record, /versions.json
FROM docker:29.5.3-dind
RUN apk add --no-cache --upgrade openssh-client openssh-server bash jq python3 \
 && adduser -D -s /bin/bash deploy && addgroup deploy docker && echo 'deploy:*' | chpasswd -e \
 && install -d -o deploy -g deploy -m 755 /srv/app /srv/deploys \
 && install -d -o deploy -g deploy -m 700 /home/deploy/.ssh
COPY sshd_config /etc/ssh/sshd_config
COPY deploy-agent /usr/local/bin/deploy-agent
COPY compose.yaml /srv/app/compose.yaml
COPY host-entrypoint.sh /usr/local/bin/host-entrypoint.sh
RUN chmod 755 /usr/local/bin/deploy-agent /usr/local/bin/host-entrypoint.sh && chmod 644 /srv/app/compose.yaml
ENTRYPOINT ["/usr/local/bin/host-entrypoint.sh"]
# its Docker API is only a local unix socket (no TCP port): the only way in from the network is SSH as "deploy"
CMD ["dockerd", "--host=unix:///var/run/docker.sock"]
