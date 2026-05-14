storage "consul" {
  address = "127.0.0.1:8500"
  path    = "vault/"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

seal "awskms" {
  region     = "REGION"
  kms_key_id = "KMS_KEY_ID"
}

api_addr     = "http://IP_ADDRESS:8200"
cluster_addr = "https://IP_ADDRESS:8201"
ui           = true
