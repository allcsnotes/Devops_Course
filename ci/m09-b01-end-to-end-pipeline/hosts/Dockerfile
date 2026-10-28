# bg-host: one "server" per environment (staging-01, prod-01), both built from this ONE file.
#  - its own Docker engine (docker:29.5.3-dind, privileged as Docker-in-Docker needs): it runs the load balancer,
#    the data layer and the two colours of the app
#  - an SSH server: the pipeline logs in as user "deploy", whose key may ONLY run the deploy agent (forced command)
#  - a read-only HTTP endpoint on port 8080 that serves the deployment record, /versions.json
FROM docker:29.5.3-dind
RUN apk add --no-cache --upgrade openssh-client openssh-server bash jq python3 curl coreutils tzdata \
 && adduser -D -s /bin/bash deploy && addgroup deploy docker && echo 'deploy:*' | chpasswd -e \
 && install -d -o deploy -g deploy -m 755 /srv/app /srv/deploys /srv/lb /srv/lb/conf.d /srv/lb/log \
 && install -d -o deploy -g deploy -m 700 /home/deploy/.ssh /srv/app/secrets
COPY sshd_config /etc/ssh/sshd_config
COPY deploy-agent /usr/local/bin/deploy-agent
COPY compose.yaml data.yaml /srv/app/
COPY lb/site.conf /srv/lb/conf.d/site.conf
COPY host-entrypoint.sh /usr/local/bin/host-entrypoint.sh
RUN chmod 755 /usr/local/bin/deploy-agent /usr/local/bin/host-entrypoint.sh \
 && chmod 644 /srv/app/compose.yaml /srv/app/data.yaml /srv/lb/conf.d/site.conf \
 && printf 'map $host $pool {\n    default blue;\n}\n' > /srv/lb/conf.d/route.conf \
 && chown -R deploy:deploy /srv/app /srv/lb
ENTRYPOINT ["/usr/local/bin/host-entrypoint.sh"]
# its Docker API is only a local unix socket (no TCP port): the only way in from the network is SSH as "deploy"
CMD ["dockerd", "--host=unix:///var/run/docker.sock"]
