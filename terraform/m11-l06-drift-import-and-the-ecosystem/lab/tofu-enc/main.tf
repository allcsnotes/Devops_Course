terraform {
  encryption {
    key_provider "pbkdf2" "lab" {
      passphrase = "fake-demo-passphrase-123" # FAKE lab value
    }
    method "aes_gcm" "lab" {
      keys = key_provider.pbkdf2.lab
    }
    state {
      method = method.aes_gcm.lab
    }
  }
}

resource "terraform_data" "media" {
  input = "allcs-media-dev"
}
