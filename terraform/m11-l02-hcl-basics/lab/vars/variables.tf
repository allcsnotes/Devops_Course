variable "env" {
  type        = string
  description = "Environment name"
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "env must be dev, staging or prod."
  }
}

variable "db_password" {
  type        = string
  description = "Database password (demo value only)"
  sensitive   = true
}
