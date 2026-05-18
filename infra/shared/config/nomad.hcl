datacenter = "dc1"
data_dir   = "/data/nomad"

acl {
  enabled = true
}

server {
  enabled          = true
  bootstrap_expect = 3
}

client {
  enabled = true
}

consul {
  address = "127.0.0.1:8500"
}

vault {
  enabled         = true
  address         = "http://IP_ADDRESS:8200"
  tls_skip_verify = true

  default_identity {
    aud = ["vault.io"]
    ttl = "1h"
  }
}

plugin "docker" {
  config {
    allow_privileged = true
    volumes {
      enabled = true
    }
  }
}

client {
  host_volume "drone-data" {
    path      = "/opt/drone/data"
    read_only = false
  }
}
