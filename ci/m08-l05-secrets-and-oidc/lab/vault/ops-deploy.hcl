# the deploy job may read one secret, nothing else
path "secret/data/allcsvideos/deploy" {
  capabilities = ["read"]
}
