# PITFALL, staged on purpose: a secret baked into an image (FAKE demo value)
source "docker" "leaky" {
  image  = "allcs/web:1.0.2"
  pull   = false
  commit = true
}

build {
  sources = ["source.docker.leaky"]

  provisioner "shell" {
    inline = ["echo 'DB_PASSWORD=demo-password-123' > /etc/allcs.env"]
  }

  post-processor "docker-tag" {
    repository = "allcs/web"
    tags       = ["leaky"]
  }
}
