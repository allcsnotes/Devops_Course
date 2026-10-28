# Vault server in "real" (non-dev) mode for the lab: file storage on a volume, sealed at start, unsealed by key holders.
# LAB ONLY: plain HTTP on a private Docker network. A real server listens with TLS (tls_cert_file / tls_key_file).
storage "file" {
  path = "/vault/file"
}
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}
api_addr      = "http://vault:8200"
disable_mlock = true
ui            = false
