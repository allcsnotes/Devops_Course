# allcs-ops: Asha's ops box for the M19-L04 lab. Only standard tools: python3 (stdlib), curl, jq.
FROM python:3.13.16-slim
RUN apt-get update && apt-get install -y --no-install-recommends curl jq \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
LABEL course=devops
