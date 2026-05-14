job "wordpress" {
  datacenters = ["dc1"]
  type        = "service"

  group "wordpress" {
    count = 1

    network {
      port "http" { to = 80 }
    }

    task "wordpress" {
      driver = "docker"

      config {
        image = "wordpress:php8.1-apache"
        ports = ["http"]
      }

      env {
        WORDPRESS_DB_HOST     = "nomad-k8s-dev-mysql.ch6qc0sa8961.us-west-1.rds.amazonaws.com"
        WORDPRESS_DB_USER     = "admin"
        WORDPRESS_DB_PASSWORD = "KaW5mKRLeLQ4g6gos0tzUuQy"
        WORDPRESS_DB_NAME     = "wordpress"
      }

      resources {
        cpu    = 300
        memory = 256
      }

      service {
        name = "wordpress"
        port = "http"

        check {
          type     = "http"
          path     = "/"
          interval = "10s"
          timeout  = "3s"
        }
      }
    }
  }
}
