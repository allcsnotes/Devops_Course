variable "env" {
type = string
    default="dev"
}
output "name" {
  value = "allcs-${var.env}"
}
