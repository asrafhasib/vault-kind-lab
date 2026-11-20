# Read only the web application's development secret.
path "secret/data/shop/dev/web" {
  capabilities = ["read"]
}

# Metadata access supports KV v2 metadata inspection.
path "secret/metadata/shop/dev/web" {
  capabilities = ["read", "list"]
}
