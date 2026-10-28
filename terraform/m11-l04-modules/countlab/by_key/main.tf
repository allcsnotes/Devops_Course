variable "zones" {
  type = map(string)
  default = {
    a = "us-east-1a"
    b = "us-east-1b"
    c = "us-east-1c"
  }
}

resource "terraform_data" "subnet" {
  for_each         = var.zones
  triggers_replace = each.value
}
