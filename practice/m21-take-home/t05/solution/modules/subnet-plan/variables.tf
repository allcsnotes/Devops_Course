variable "environment" {
  description = "Environment name: dev, staging or prod."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "The VPC range, a /16 such as 10.0.0.0/16."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr must be a valid IPv4 /16, for example 10.0.0.0/16."
  }
}

variable "azs" {
  description = "Availability zone names, one subnet of each tier per zone."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 1 && length(var.azs) <= 4 && length(distinct(var.azs)) == length(var.azs)
    error_message = "azs must list 1 to 4 distinct zone names."
  }

  validation {
    condition     = var.environment != "prod" || length(var.azs) >= 2
    error_message = "prod needs at least 2 availability zones."
  }
}

variable "tags" {
  description = "Extra tags. owner and cost-center are required."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k in ["owner", "cost-center"] : contains(keys(var.tags), k)])
    error_message = "tags must include owner and cost-center."
  }
}
