datacenter = "dc1"
data_dir   = "/opt/nomad"

server {
  enabled          = true
  bootstrap_expect = SERVER_COUNT
}

client {
  enabled = true
}

consul {
  address = "127.0.0.1:8500"
}

vault {
  enabled = true
  address = "http://active.vault.service.consul:8200"
}

plugin "docker" {
  config {
    allow_privileged = true
  }
}
