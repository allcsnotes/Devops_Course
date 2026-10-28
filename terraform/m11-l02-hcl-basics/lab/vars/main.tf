locals {
  name_prefix = "allcs-${var.env}"
  common_tags = { Project = "allcsvideos", Env = var.env }
}

output "bucket_name" {
  value = "${local.name_prefix}-media"
}

output "tags" {
  value = merge(local.common_tags, { Name = "media-${var.env}" })
}

output "db_password" {
  value = var.db_password
}
