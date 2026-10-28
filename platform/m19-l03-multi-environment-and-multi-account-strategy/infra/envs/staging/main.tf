terraform {
  required_version = "~> 1.16"
}

variable "env" { type = string }
variable "account_id" { type = string }
variable "caller_account" { type = string }
variable "cidr" { type = string }
variable "node_size" { type = string }
variable "node_count" { type = number }
variable "db_class" { type = string }
variable "db_multi_az" { type = bool }

module "platform" {
  source         = "../../modules/platform"
  env            = var.env
  account_id     = var.account_id
  caller_account = var.caller_account
  cidr           = var.cidr
  node_size      = var.node_size
  node_count     = var.node_count
  db_class       = var.db_class
  db_multi_az    = var.db_multi_az
}

output "summary" { value = module.platform.summary }
