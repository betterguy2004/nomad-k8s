job "wordpress" {
  datacenters = ["dc1"]
  type        = "service"

  group "wordpress" {
    count = 2

    network {
      port "fpm" { to = 9000 }
    }

    vault {
      policies = ["wordpress"]
    }

    task "wordpress" {
      driver = "docker"

      config {
        image = "asdads6495/wordpress:latest"
        ports = ["fpm"]
      }

      template {
        data = <<EOF
{{with secret "database/creds/wordpress"}}
WORDPRESS_DB_HOST={{key "rds/endpoint"}}
WORDPRESS_DB_USER={{.Data.username}}
WORDPRESS_DB_PASSWORD={{.Data.password}}
WORDPRESS_DB_NAME=wordpress
{{end}}
{{with secret "secret/data/wordpress"}}
WORDPRESS_AUTH_KEY={{.Data.data.auth_key}}
WORDPRESS_SECURE_AUTH_KEY={{.Data.data.secure_auth_key}}
WORDPRESS_LOGGED_IN_KEY={{.Data.data.logged_in_key}}
WORDPRESS_NONCE_KEY={{.Data.data.nonce_key}}
WP_OFFLOAD_MEDIA_BUCKET={{.Data.data.s3_bucket}}
WP_OFFLOAD_MEDIA_REGION={{.Data.data.s3_region}}
{{end}}
EOF
        destination = "secrets/env"
        env         = true
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "wordpress"
        port = "fpm"

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }

        connect {
          sidecar_service {}
        }
      }
    }
  }

  update {
    max_parallel     = 1
    canary           = 1
    min_healthy_time = "30s"
    healthy_deadline = "5m"
    auto_revert      = true
  }
}
