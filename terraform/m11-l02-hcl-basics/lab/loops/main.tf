variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

# count: N copies, addressed by number
resource "terraform_data" "by_count" {
  count = length(var.azs)
  input = cidrsubnet("10.0.0.0/16", 8, count.index + 1)
}

# for_each: one copy per key, addressed by name
resource "terraform_data" "by_key" {
  for_each = toset(var.azs)
  input    = "subnet in ${each.key}"
}
