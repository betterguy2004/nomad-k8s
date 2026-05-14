consul {
  address = "127.0.0.1:8500"
}

vault {
  address     = "http://active.vault.service.consul:8200"
  renew_token = true
}

log_level = "info"
