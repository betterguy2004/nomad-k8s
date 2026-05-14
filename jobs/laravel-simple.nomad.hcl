job "laravel" {
  datacenters = ["dc1"]
  type        = "service"

  group "laravel" {
    count = 1

    network {
      port "http" { to = 80 }
    }

    task "laravel" {
      driver = "docker"

      config {
        image = "webdevops/php-nginx:8.2"
        ports = ["http"]
      }

      env {
        WEB_DOCUMENT_ROOT = "/app/public"
      }

      resources {
        cpu    = 300
        memory = 256
      }

      service {
        name = "laravel"
        port = "http"

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "3s"
        }
      }
    }
  }
}
