variable "docker_image_tag" {
  description = "Docker image tag for Laravel"
  type        = string
  default     = "latest"
}

job "laravel" {
  datacenters = ["dc1"]
  type        = "service"

  group "laravel" {
    count = 2

    network {
      port "fpm" { to = 9000 }
    }

    vault {
      policies = ["laravel"]
    }

    task "migrate" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image   = "asdads6495/laravel:${var.docker_image_tag}"
        command = "php"
        args    = ["artisan", "migrate", "--force"]
      }

      template {
        data = <<EOF
{{with secret "database/creds/laravel"}}
DB_HOST={{key "rds/endpoint"}}
DB_USERNAME={{.Data.username}}
DB_PASSWORD={{.Data.password}}
DB_DATABASE=laravel
{{end}}
EOF
        destination = "secrets/env"
        env         = true
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }

    task "laravel" {
      driver = "docker"

      config {
        image = "asdads6495/laravel:${var.docker_image_tag}"
        ports = ["fpm"]
      }

      template {
        data = <<EOF
{{with secret "database/creds/laravel"}}
DB_HOST={{key "rds/endpoint"}}
DB_USERNAME={{.Data.username}}
DB_PASSWORD={{.Data.password}}
DB_DATABASE=laravel
{{end}}
{{with secret "secret/data/laravel"}}
APP_KEY={{.Data.data.app_key}}
AWS_BUCKET={{.Data.data.s3_bucket}}
AWS_DEFAULT_REGION={{.Data.data.s3_region}}
{{end}}
APP_ENV=production
APP_DEBUG=false
EOF
        destination = "secrets/env"
        env         = true
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "laravel"
        port = "fpm"

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
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
    auto_promote     = true
  }
}
