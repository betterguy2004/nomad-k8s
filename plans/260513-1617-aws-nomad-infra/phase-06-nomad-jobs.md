---
phase: 6
title: "Nomad Jobs"
status: complete
priority: P1
effort: "3h"
dependencies: [5]
---

# Phase 6: Nomad Jobs

## Overview

Deploy system jobs (Nginx LB, Consul Template) and application jobs (WordPress, Laravel) to Nomad cluster with Consul service registration and Vault integration.

## Requirements

**Functional:**
- Nginx as system job with Consul Template for dynamic upstreams
- WordPress with WP Offload Media plugin, Vault DB creds
- Laravel with PHP-FPM, migration prestart task, Vault DB creds
- All services registered in Consul

**Non-functional:**
- Health checks for all services
- Resource limits defined
- Rolling updates with canary deployment

## Architecture

```
Nomad Jobs:
┌─────────────────────────────────────────────────────────────────┐
│ System Jobs (all nodes)                                         │
│  ┌───────────────────┐  ┌───────────────────────────────────┐   │
│  │ nginx-lb          │  │ consul-template                   │   │
│  │ Port: 80          │  │ Watches: Consul catalog           │   │
│  │ Upstream: dynamic │  │ Generates: nginx.conf             │   │
│  └───────────────────┘  └───────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│ Service Jobs                                                    │
│  ┌───────────────────┐  ┌───────────────────────────────────┐   │
│  │ wordpress         │  │ laravel                           │   │
│  │ Count: 2          │  │ Count: 2                          │   │
│  │ Port: 9000 (FPM)  │  │ Port: 9000 (FPM)                  │   │
│  │ Vault: db creds   │  │ Vault: db creds                   │   │
│  └───────────────────┘  │ Prestart: migrate                 │   │
│                         └───────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Related Code Files

**Create:**
- `jobs/system/nginx-lb.nomad.hcl`
- `jobs/system/consul-template.nomad.hcl`
- `jobs/wordpress.nomad.hcl`
- `jobs/laravel.nomad.hcl`
- `jobs/vars/dev.vars`
- `docker/wordpress/Dockerfile`
- `docker/laravel/Dockerfile`
- `docker/laravel/nginx.conf`

## Implementation Steps

### System Jobs

1. **Create Nginx LB job**
   ```hcl
   # jobs/system/nginx-lb.nomad.hcl
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
       server 127.0.0.1:65535;  # placeholder
       {{end}}
     }
     
     upstream laravel {
       {{range service "laravel"}}
       server {{.Address}}:{{.Port}};
       {{else}}
       server 127.0.0.1:65535;
       {{end}}
     }
     
     server {
       listen 80;
       
       location /wp/ {
         proxy_pass http://wordpress;
         proxy_set_header Host $host;
         proxy_set_header X-Real-IP $remote_addr;
       }
       
       location / {
         proxy_pass http://laravel;
         proxy_set_header Host $host;
         proxy_set_header X-Real-IP $remote_addr;
       }
     }
   }
   EOF
           destination = "local/nginx.conf"
           change_mode = "signal"
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
   ```

2. **Create Consul Template job** (optional if using Nginx template block)
   ```hcl
   # jobs/system/consul-template.nomad.hcl
   # Skip if using Nomad's built-in template block
   ```

### Application Jobs

3. **Create WordPress Dockerfile**
   ```dockerfile
   # docker/wordpress/Dockerfile
   FROM wordpress:php8.2-fpm
   
   # Install WP-CLI
   RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
       && chmod +x wp-cli.phar \
       && mv wp-cli.phar /usr/local/bin/wp
   
   # Install S3 Offload plugin dependencies
   RUN docker-php-ext-install exif
   
   # Custom PHP config
   COPY php.ini /usr/local/etc/php/conf.d/custom.ini
   
   EXPOSE 9000
   ```

4. **Create WordPress Nomad job**
   ```hcl
   # jobs/wordpress.nomad.hcl
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
   ```

5. **Create Laravel Dockerfile**
   ```dockerfile
   # docker/laravel/Dockerfile
   FROM php:8.2-fpm
   
   # Install extensions
   RUN docker-php-ext-install pdo pdo_mysql opcache
   
   # Install Composer
   COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
   
   WORKDIR /var/www
   
   # Copy application
   COPY . .
   RUN composer install --no-dev --optimize-autoloader
   
   # Permissions
   RUN chown -R www-data:www-data storage bootstrap/cache
   
   EXPOSE 9000
   ```

6. **Create Laravel Nomad job**
   ```hcl
   # jobs/laravel.nomad.hcl
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
       
       # Migration prestart task
       task "migrate" {
         driver = "docker"
         
         lifecycle {
           hook    = "prestart"
           sidecar = false
         }
         
         config {
           image   = "asdads6495/laravel:latest"
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
           image = "asdads6495/laravel:latest"
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
   APP_KEY=base64:{{.Data.data.app_key}}
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
   ```

7. **Create variables file**
   ```hcl
   # jobs/vars/dev.vars
   datacenter    = "dc1"
   docker_image_tag = "latest"
   wordpress_count  = 2
   laravel_count    = 2
   ```

8. **Build and push Docker images**
   ```bash
   # Build WordPress
   cd docker/wordpress
   docker build -t asdads6495/wordpress:latest .
   docker push asdads6495/wordpress:latest
   
   # Build Laravel
   cd ../laravel
   docker build -t asdads6495/laravel:latest .
   docker push asdads6495/laravel:latest
   ```

9. **Deploy jobs**
   ```bash
   # System jobs first
   nomad job run jobs/system/nginx-lb.nomad.hcl
   
   # Application jobs
   nomad job run -var-file=jobs/vars/dev.vars jobs/wordpress.nomad.hcl
   nomad job run -var-file=jobs/vars/dev.vars jobs/laravel.nomad.hcl
   ```

10. **Store RDS endpoint in Consul KV**
    ```bash
    consul kv put rds/endpoint "mysql.private-subnet.local:3306"
    ```

## Success Criteria

- [ ] Nginx LB running on all 3 nodes
- [ ] `nomad job status nginx-lb` shows healthy
- [ ] WordPress allocations running with healthy checks
- [ ] Laravel allocations running, migrations completed
- [ ] Services registered in Consul: `consul catalog services`
- [ ] Vault credentials rotating (check Vault audit log)
- [ ] Access WordPress via http://domain/wp/
- [ ] Access Laravel via http://domain/

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Docker pull rate limit | Use Docker Hub auth or mirror |
| Vault template fails | Check Nomad alloc logs, verify policy |
| Migration fails | Check prestart task logs, verify DB access |
| Service discovery lag | Increase health check interval |
