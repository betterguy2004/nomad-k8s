job "drone-vault" {
  datacenters = ["dc1"]
  type        = "service"

  group "vault-extension" {
    count = 1

    network {
      port "http" { to = 3000 }
    }

    vault {
      policies = ["drone"]
    }

    task "drone-vault" {
      driver = "docker"

      config {
        image = "drone/vault:1.3"
        ports = ["http"]
      }

      template {
        data = <<EOF
{{with secret "secret/data/drone/server"}}
DRONE_SECRET={{.Data.data.rpc_secret}}
{{end}}
{{with secret "secret/data/drone/vault-extension"}}
VAULT_TOKEN={{.Data.data.token}}
{{end}}
VAULT_ADDR=http://active.vault.service.consul:8200
EOF
        destination = "secrets/env"
        env         = true
      }

      resources {
        cpu    = 100
        memory = 128
      }

      service {
        name = "drone-vault"
        port = "http"

        check {
          type     = "http"
          path     = "/healthz"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
