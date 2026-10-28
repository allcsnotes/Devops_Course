# Lab stand-in for the allcsvideos platform module: the inputs a real one takes, but terraform_data
# instead of aws_vpc, aws_eks_cluster and aws_db_instance, so it runs with no cloud and no credentials.
variable "env" { type = string }
variable "account_id" { type = string }
variable "caller_account" { type = string } # lab stand-in for data.aws_caller_identity
variable "cidr" { type = string }
variable "node_size" { type = string }
variable "node_count" { type = number }
variable "db_class" { type = string }
variable "db_multi_az" { type = bool }

resource "terraform_data" "account_guard" {
  input = var.account_id
  lifecycle {
    precondition {
      condition     = var.caller_account == var.account_id
      error_message = "Credentials are for account ${var.caller_account}, but ${var.env} lives in ${var.account_id}."
    }
  }
}

resource "terraform_data" "vpc" {
  input = { name = "allcs-${var.env}", cidr = var.cidr }
}

resource "terraform_data" "cluster" {
  input = { name = "allcs-${var.env}", node_size = var.node_size, nodes = var.node_count }
}

resource "terraform_data" "database" {
  input = { name = "allcs-${var.env}-db", class = var.db_class, multi_az = var.db_multi_az }
}

output "summary" {
  value = "${var.env} in ${var.account_id}: ${var.node_count} x ${var.node_size}, db ${var.db_class}${var.db_multi_az ? " multi-AZ" : ""}"
}
