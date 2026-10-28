variable "cluster_name" {
  type    = string
  default = "allcs-eks"
}

variable "kubernetes_version" {
  type    = string
  default = "1.37"
}

variable "node_instance_type" {
  type        = string
  description = "Sandbox policy allows t2/t3 up to medium"
  default     = "t3.medium"
}
