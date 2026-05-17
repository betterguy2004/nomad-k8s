job "wordpress" {
  datacenters = ["dc1"]
  type        = "service"

  group "wordpress" {
    count = 2

    network {
      port "http" { to = 80 }
    }

    task "wordpress" {
      driver = "docker"

      vault {
        role = "nomad-workloads"
      }

      config {
        image = "wordpress:php8.1-apache"
        ports = ["http"]
      }

      template {
        data = <<EOF
{{- with secret "secret/data/wordpress/keys" }}
WORDPRESS_AUTH_KEY={{ .Data.data.auth_key }}
WORDPRESS_SECURE_AUTH_KEY={{ .Data.data.secure_auth_key }}
WORDPRESS_LOGGED_IN_KEY={{ .Data.data.logged_in_key }}
WORDPRESS_NONCE_KEY={{ .Data.data.nonce_key }}
WORDPRESS_AUTH_SALT={{ .Data.data.auth_salt }}
WORDPRESS_SECURE_AUTH_SALT={{ .Data.data.secure_auth_salt }}
WORDPRESS_LOGGED_IN_SALT={{ .Data.data.logged_in_salt }}
WORDPRESS_NONCE_SALT={{ .Data.data.nonce_salt }}
{{- end }}
{{- with secret "secret/data/wordpress/db" }}
WORDPRESS_DB_HOST={{ .Data.data.host }}
WORDPRESS_DB_USER={{ .Data.data.user }}
WORDPRESS_DB_PASSWORD={{ .Data.data.password }}
WORDPRESS_DB_NAME={{ .Data.data.name }}
{{- end }}
EOF
        destination = "secrets/wordpress.env"
        env         = true
      }

      env {
        WORDPRESS_CONFIG_EXTRA = "define('WP_HOME', 'https://wp.hungpq.io.vn'); define('WP_SITEURL', 'https://wp.hungpq.io.vn'); define('FORCE_SSL_ADMIN', true); define('COOKIE_DOMAIN', 'wp.hungpq.io.vn'); define('ADMIN_COOKIE_PATH', '/'); define('COOKIEPATH', '/'); define('SITECOOKIEPATH', '/'); if (strpos($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '', 'https') !== false) { $_SERVER['HTTPS'] = 'on'; }"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "wordpress"
        port = "http"

        check {
          type     = "http"
          path     = "/wp-admin/install.php"
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
  }
}
