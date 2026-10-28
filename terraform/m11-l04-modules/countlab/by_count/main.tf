variable "zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

resource "terraform_data" "subnet" {
  count            = length(var.zones)
  triggers_replace = var.zones[count.index]
}
