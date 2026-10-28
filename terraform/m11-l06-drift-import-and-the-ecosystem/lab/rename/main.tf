# stands in for the media bucket: terraform_data is built in, no cloud, no credentials
resource "terraform_data" "media" {
  input = "allcs-media-dev"
}
