# M18-L05 lab tools: Checkov 3.3.30 + Conftest 0.71.1 (OPA 1.21.1) + jq, as user asha. Pinned by digest.
FROM openpolicyagent/conftest:v0.71.1@sha256:0e77cdf7c1fcde035f3c579e4aaa6664ee2a8be5777eaa9af9f520cdd02280c0 AS conftest
FROM bridgecrew/checkov:3.3.30@sha256:4b65e89f1fde292249fc0aa0d0db43302c036dfe39f7370b2d3517571082b894
RUN apt-get update && apt-get install -y --no-install-recommends jq tmux && rm -rf /var/lib/apt/lists/* \
 && useradd -m -s /bin/bash asha
COPY --from=conftest /usr/local/bin/conftest /usr/local/bin/conftest
USER asha
WORKDIR /home/asha/allcsvideos
ENV PS1='asha@laptop:\w\$ '
ENTRYPOINT []
CMD ["bash"]
