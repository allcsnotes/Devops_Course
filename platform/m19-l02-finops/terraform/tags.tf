# Cost tags for every AWS resource of allcsvideos (extends the M11-B01 provider block: Team and CostCenter added)
variable "env" {
  type    = string
  default = "prod"
}

variable "team" {
  type    = string
  default = "platform"
}

variable "cost_center" {
  type        = string
  description = "finance cost center, e.g. cc-1042"
  validation {
    condition     = can(regex("^cc-[0-9]{4}$", var.cost_center))
    error_message = "cost_center must look like cc-1234 (ask finance for yours)."
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Project    = "allcsvideos"
      Env        = var.env
      Team       = var.team
      CostCenter = var.cost_center
      ManagedBy  = "terraform"
    }
  }
}

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
