path "secret/data/drone/*" {
  capabilities = ["read"]
}

path "secret/metadata/drone/*" {
  capabilities = ["list"]
}
