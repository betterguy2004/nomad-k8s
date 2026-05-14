job "drone-server" {
  datacenters = ["dc1"]
  type        = "service"

  group "drone" {
    count = 1

    network {
      port "http" { to = 80 }
    }

    volume "drone-data" {
      type      = "host"
      source    = "drone-data"
      read_only = false
    }

    vault {
      policies = ["drone"]
    }

    task "server" {
      driver = "docker"

      config {
        image = "drone/drone:2"
        ports = ["http"]
      }

      volume_mount {
        volume      = "drone-data"
        destination = "/data"
      }

      template {
        data = <<EOF
{{with secret "secret/data/drone"}}
DRONE_GITHUB_CLIENT_ID={{.Data.data.github_client_id}}
DRONE_GITHUB_CLIENT_SECRET={{.Data.data.github_client_secret}}
DRONE_RPC_SECRET={{.Data.data.rpc_secret}}
{{end}}
DRONE_SERVER_HOST=drone.hungpq.io.vn
DRONE_SERVER_PROTO=https
DRONE_DATABASE_DRIVER=sqlite3
DRONE_DATABASE_DATASOURCE=/data/database.sqlite
DRONE_USER_CREATE=username:betterguy2004,admin:true
EOF
        destination = "secrets/env"
        env         = true
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "drone-server"
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
