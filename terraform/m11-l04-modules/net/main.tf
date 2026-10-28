terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags { tags = { Project = "allcsvideos", ManagedBy = "terraform" } }
}

module "staging_net" {
  source = "./modules/network"
  name   = "allcs-${terraform.workspace}"
  cidr   = "10.1.0.0/16"
  zones  = ["us-east-1a", "us-east-1b"]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name            = "allcs-registry-demo"
  cidr            = "10.2.0.0/16"
  azs             = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.2.101.0/24", "10.2.102.0/24"]
  private_subnets = ["10.2.1.0/24", "10.2.2.0/24"]
}

output "staging_vpc" { value = module.staging_net.vpc_id }
output "staging_subnets" { value = module.staging_net.public_subnet_ids }
