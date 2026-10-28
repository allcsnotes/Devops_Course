variable "db_source" {
  description = "init = a brand-new, seeded database; pitr = restore from the newest base backup + archived WAL in the bucket"
  type        = string
  default     = "init"
  validation {
    condition     = contains(["init", "pitr"], var.db_source)
    error_message = "db_source must be init or pitr."
  }
}

variable "archive_timeout" {
  description = "PostgreSQL archive_timeout: force a WAL switch (and so an upload) at least this often. 0 = only when a 16 MB file fills"
  type        = string
  default     = "0"
}

variable "db_admin_password" {
  description = "postgres superuser password (FAKE lab value, from the break-glass folder)"
  type        = string
  sensitive   = true
}

variable "vault_snapshot_token" {
  description = "Vault token for the backup agent, policy snapshot only (lab value, from the break-glass folder)"
  type        = string
  sensitive   = true
}
