packer {
  required_plugins {
    docker = {
      source  = "github.com/hashicorp/docker"
      version = "= 1.1.4"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "= 1.1.6"
    }
  }
}

variable "version" {
  type        = string
  description = "Image version (semver), e.g. 1.0.0"
}

variable "revision" {
  type        = string
  description = "Git commit the image is built from"
  default     = "unknown"
}

locals {
  repository = "allcs/web"
}

# Start from Ubuntu 24.04, pinned by digest
source "docker" "ubuntu" {
  image  = "ubuntu:24.04@sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac"
  commit = true
  changes = [
    "EXPOSE 80",
    "ENTRYPOINT [\"/usr/local/bin/allcs-start\"]",
    "LABEL org.opencontainers.image.version=${var.version}",
    "LABEL org.opencontainers.image.revision=${var.revision}",
    "LABEL course=devops",
  ]
}

build {
  sources = ["source.docker.ubuntu"]

  # security updates, then Python (Ansible needs it)
  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    inline = [
      "apt-get update",
      "apt-get upgrade -y",
      "apt-get install -y --no-install-recommends python3",
    ]
  }

  # the same roles as the fleet, from lesson 2
  provisioner "ansible" {
    playbook_file   = "ansible/image.yml"
    user            = "root"
    groups          = ["web"] # so group_vars/web.yml applies
    extra_arguments = ["--extra-vars", "image_version=${var.version}"]
  }

  # no package lists in the image: smaller
  provisioner "shell" {
    inline = ["apt-get clean", "rm -rf /var/lib/apt/lists/*"]
  }

  post-processor "docker-tag" {
    repository = local.repository
    tags       = [var.version]
  }
}
