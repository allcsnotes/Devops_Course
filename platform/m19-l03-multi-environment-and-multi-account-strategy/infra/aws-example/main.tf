# The same idea on real AWS (validated offline with terraform validate; never applied in this lab).
terraform {
  required_version = "~> 1.16"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.69" }
  }
}

variable "env" { type = string }
variable "account_id" { type = string }

provider "aws" {
  region              = "us-east-1"
  allowed_account_ids = [var.account_id] # refuse to run against any other account

  assume_role {
    role_arn     = "arn:aws:iam::${var.account_id}:role/allcs-deploy"
    session_name = "terraform-${var.env}"
  }

  default_tags {
    tags = { Project = "allcsvideos", Env = var.env }
  }
}
