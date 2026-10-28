# shiftleft-dev: the team's lab machine (same recipe as the Module 8 CI lab image, M08-L02 / M11-B01): Ubuntu 24.04,
# Git from Ubuntu's packages, tzdata (+05:30), tmux (only used to capture real terminal screens), curl + jq (Gitea REST
# API), tree, python3 + venv, plus the three scanners of this lesson, pinned:
#   gitleaks 8.30.1  copied unchanged from the official image zricethezav/gitleaks:v8.30.1 (released 2026-03-21)
#   semgrep 1.182.0  from PyPI into /opt/semgrep (the same version as the semgrep/semgrep:1.182.0 image the pipeline uses)
#   trivy 0.76.0     copied from aquasec/trivy:0.76.0, pinned by digest (the March 2026 compromise, M07-L03)
# Accounts asha, priya, rahul stand in for three laptops.
FROM zricethezav/gitleaks:v8.30.1 AS gitleaks
FROM aquasec/trivy:0.76.0@sha256:2416d1f74045b57274df1a340eee6b510cacd73c66a6ccb8da092b117eb7d222 AS trivy
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive TZ=Asia/Kolkata
RUN apt-get update && apt-get install -y --no-install-recommends git tree tzdata tmux less nano curl jq ca-certificates python3 python3-venv \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime && echo Asia/Kolkata > /etc/timezone \
    && (userdel -r ubuntu 2>/dev/null || true) && groupadd dev \
    && for u in asha priya rahul; do useradd -m -s /bin/bash -G dev $u; done
RUN python3 -m venv /opt/semgrep && /opt/semgrep/bin/pip install --no-cache-dir semgrep==1.182.0 && ln -s /opt/semgrep/bin/semgrep /usr/local/bin/semgrep
COPY --from=gitleaks /usr/bin/gitleaks /usr/local/bin/gitleaks
COPY --from=trivy /usr/local/bin/trivy /usr/local/bin/trivy
CMD ["sleep", "infinity"]
