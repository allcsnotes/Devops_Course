# The Ansible control node (Asha's admin box). No systemd needed, run with --init.
# Ansible itself is NOT baked in: it is installed with pip into a venv (setup-control.sh, or live in the lesson).
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-venv python3-pip openssh-client tmux sudo less nano curl ca-certificates git tree \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
CMD ["sleep", "infinity"]
