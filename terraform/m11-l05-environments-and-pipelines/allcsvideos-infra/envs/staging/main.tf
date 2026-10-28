terraform {
  required_version = "~> 1.16"
  required_providers {
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

variable "env" { type = string }
variable "cidr" { type = string }
variable "zones" { type = list(string) }

module "network" {
  source = "../../modules/network"
  name   = "allcs-${var.env}"
  cidr   = var.cidr
  zones  = var.zones
}

output "network" { value = module.network }
