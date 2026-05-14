path "database/creds/wordpress" {
  capabilities = ["read"]
}

path "secret/data/wordpress/*" {
  capabilities = ["read"]
}

path "secret/metadata/wordpress/*" {
  capabilities = ["list"]
}
