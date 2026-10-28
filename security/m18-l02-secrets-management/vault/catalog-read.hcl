# catalog-read: what the catalog service may do in Vault, and nothing else
path "allcs/data/catalog/*" {
  capabilities = ["read"]
}
path "database/creds/catalog-ro" {
  capabilities = ["read"]
}
