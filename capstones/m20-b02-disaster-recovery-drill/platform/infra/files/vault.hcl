# Vault 2.1.2 for allcsvideos production: integrated storage (raft) on its own volume, starts sealed.
# LAB ONLY: plain HTTP on a private Docker network. A real server listens with TLS (tls_cert_file / tls_key_file).
storage "raft" {
  path    = "/vault/file"
  node_id = "vault-1"
}
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}
api_addr      = "http://10.0.202.11:8200"
cluster_addr  = "http://10.0.202.11:8201"
disable_mlock = true
ui            = false
