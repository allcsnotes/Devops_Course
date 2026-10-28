# The production environment's infrastructure, as code. LAB STAND-IN: in AWS this would be the VPC, RDS, Vault on EC2,
# the monitoring hosts (module 11 built the real AWS version). Here the same idea runs locally: the Docker provider creates
# the database server, Vault, the backup agent, Prometheus and Grafana as containers with their own volumes.
terraform {
  required_version = "~> 1.16.0"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "4.6.0"
    }
  }
  # state lives OFF-SITE, in the backup bucket (Terraform's http backend; on AWS: the S3 backend)
  backend "http" {
    address = "http://10.0.202.6:9000/tfstate/prod.tfstate"
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}
