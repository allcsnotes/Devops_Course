# tfci-team: the team's shared "laptop" for this lab. Ubuntu 24.04 with git, curl, jq and tree,
# plus the Terraform CLI copied from the official image hashicorp/terraform:1.16.6
# and tflint 0.64.0 from ghcr.io/terraform-linters/tflint:v0.64.0.
# The accounts asha, priya and rahul stand in for three people's laptops.
FROM hashicorp/terraform:1.16.6 AS tf
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends git tree less nano curl jq ca-certificates unzip \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && (userdel -r ubuntu 2>/dev/null || true) && groupadd dev \
    && for u in asha priya rahul; do useradd -m -s /bin/bash -G dev $u; done
COPY --from=tf /bin/terraform /usr/local/bin/terraform
COPY --from=ghcr.io/terraform-linters/tflint:v0.64.0 /usr/local/bin/tflint /usr/local/bin/tflint
CMD ["sleep", "infinity"]
