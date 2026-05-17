job "nginx-lb" {
  datacenters = ["dc1"]
  type        = "system"

  group "nginx" {
    network {
      port "http" { static = 80 }
    }

    task "nginx" {
      driver = "docker"

      config {
        image = "nginx:alpine"
        ports = ["http"]
        volumes = [
          "local/nginx.conf:/etc/nginx/nginx.conf:ro"
        ]
      }

      template {
        data = <<EOF
events { worker_connections 1024; }
http {
  upstream wordpress {
    {{range service "wordpress"}}
    server {{.Address}}:{{.Port}};
    {{else}}
    server 127.0.0.1:65535;
    {{end}}
  }

  upstream laravel {
    {{range service "laravel"}}
    server {{.Address}}:{{.Port}};
    {{else}}
    server 127.0.0.1:65535;
    {{end}}
  }

  upstream drone {
    {{range service "drone-server"}}
    server {{.Address}}:{{.Port}};
    {{else}}
    server 127.0.0.1:65535;
    {{end}}
  }

  server {
    listen 80;
    server_name drone.hungpq.io.vn;

    location / {
      proxy_pass http://drone;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_buffering off;
      chunked_transfer_encoding off;
    }
  }

  server {
    listen 80;
    server_name wp.hungpq.io.vn;
    client_max_body_size 64m;

    location / {
      proxy_pass http://wordpress;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto https;
    }
  }

  server {
    listen 80;
    server_name laravel.hungpq.io.vn;
    client_max_body_size 64m;

    location / {
      proxy_pass http://laravel;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto https;
    }
  }

  server {
    listen 80;
    server_name _ default_server;

    location /health {
      return 200 'ok';
      add_header Content-Type text/plain;
    }

    location /wp/ {
      rewrite ^/wp/(.*)$ /$1 break;
      proxy_pass http://wordpress;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /wp-admin/ {
      proxy_pass http://wordpress;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /wp-includes/ {
      proxy_pass http://wordpress;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /wp-content/ {
      proxy_pass http://wordpress;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /wp-login.php {
      proxy_pass http://wordpress;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
      proxy_pass http://laravel;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }
  }
}
EOF
        destination   = "local/nginx.conf"
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }

      resources {
        cpu    = 100
        memory = 64
      }

      service {
        name = "nginx"
        port = "http"

        check {
          type     = "http"
          path     = "/health"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
