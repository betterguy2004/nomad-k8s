path "database/creds/laravel" {
  capabilities = ["read"]
}

path "secret/data/laravel/*" {
  capabilities = ["read"]
}

path "secret/metadata/laravel/*" {
  capabilities = ["list"]
}
