---
phase: 7
title: "CI/CD Pipeline"
status: complete
priority: P2
effort: "2h"
dependencies: [6]
---

# Phase 7: CI/CD Pipeline

## Overview

Deploy Drone CI/CD on Nomad cluster with GitHub integration, Vault secrets, and automated build/deploy pipelines for WordPress and Laravel.

## Requirements

**Functional:**
- Drone server as Nomad service job
- Drone runner as Nomad system job (Docker executor)
- GitHub OAuth app integration
- Vault secrets extension for credentials
- Pipelines: build image → push DockerHub → deploy to Nomad

**Non-functional:**
- Pipeline execution < 5 minutes
- Automatic rollback on failed deployment

## Architecture

```
CI/CD Flow:
┌─────────────────────────────────────────────────────────────────┐
│ GitHub                                                          │
│  └─ Push to main branch                                         │
│       │                                                         │
│       ▼ Webhook                                                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Drone Server (Nomad service job)                            │ │
│ │  - Receives webhook                                         │ │
│ │  - Fetches secrets from Vault                               │ │
│ │  - Dispatches to runner                                     │ │
│ └─────────────────────────────────────────────────────────────┘ │
│       │                                                         │
│       ▼                                                         │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Drone Runner (Nomad system job)                             │ │
│ │  ├─ Clone repository                                        │ │
│ │  ├─ Build Docker image                                      │ │
│ │  ├─ Push to Docker Hub                                      │ │
│ │  └─ nomad job run (deploy)                                  │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Related Code Files

**Create:**
- `jobs/system/drone-server.nomad.hcl`
- `jobs/system/drone-vault.nomad.hcl` (Vault extension)
- `jobs/system/drone-runner.nomad.hcl`
- `docker/wordpress/.drone.yml`
- `docker/laravel/.drone.yml`
- `docker/nomad-deploy/Dockerfile` (helper image)
- `scripts/setup-github-oauth.md`

## Implementation Steps

### Drone Infrastructure

1. **Create GitHub OAuth App**
   - Go to GitHub Settings → Developer settings → OAuth Apps
   - New OAuth App:
     - Application name: `Nomad Drone CI`
     - Homepage URL: `https://drone.your-domain.com`
     - Authorization callback URL: `https://drone.your-domain.com/login`
   - Note Client ID and Client Secret

2. **Store Drone secrets in Vault**
   ```bash
   vault kv put secret/drone \
     github_client_id="YOUR_CLIENT_ID" \
     github_client_secret="YOUR_CLIENT_SECRET" \
     rpc_secret="$(openssl rand -hex 16)" \
     dockerhub_username="YOUR_DOCKERHUB_USER" \
     dockerhub_password="YOUR_DOCKERHUB_PASS"
   ```

3. **Create Drone Server job**
   ```hcl
   # jobs/system/drone-server.nomad.hcl
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
   ```

4. **Create Drone-Vault Extension job** (required for Vault secrets)
   ```hcl
   # jobs/system/drone-vault.nomad.hcl
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
   {{with secret "secret/data/drone"}}
   DRONE_SECRET={{.Data.data.rpc_secret}}
   {{end}}
   VAULT_ADDR=http://active.vault.service.consul:8200
   VAULT_TOKEN={{env "VAULT_TOKEN"}}
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
   ```

5. **Create Drone Runner job** (with extension config)
   ```hcl
   # jobs/system/drone-runner.nomad.hcl
   job "drone-runner" {
     datacenters = ["dc1"]
     type        = "system"
     
     group "runner" {
       vault {
         policies = ["drone"]
       }
       
       task "runner" {
         driver = "docker"
         
         config {
           image      = "drone/drone-runner-docker:1"
           privileged = true
           volumes    = [
             "/var/run/docker.sock:/var/run/docker.sock"
           ]
         }
         
         template {
           data = <<EOF
   {{with secret "secret/data/drone"}}
   DRONE_RPC_SECRET={{.Data.data.rpc_secret}}
   DRONE_SECRET_PLUGIN_TOKEN={{.Data.data.rpc_secret}}
   {{end}}
   DRONE_RPC_HOST=drone-server.service.consul
   DRONE_RPC_PROTO=http
   DRONE_RUNNER_CAPACITY=2
   DRONE_RUNNER_NAME={{env "attr.unique.hostname"}}
   DRONE_SECRET_PLUGIN_ENDPOINT=http://drone-vault.service.consul:3000
   EOF
           destination = "secrets/env"
           env         = true
         }
         
         resources {
           cpu    = 500
           memory = 512
         }
       }
     }
   }
   ```

### Application Pipelines

5. **Create nomad-deploy helper image**
   ```dockerfile
   # docker/nomad-deploy/Dockerfile
   FROM alpine:3.18
   
   RUN apk add --no-cache curl bash jq
   
   # Install Nomad CLI
   RUN curl -sL https://releases.hashicorp.com/nomad/1.7.0/nomad_1.7.0_linux_amd64.zip -o nomad.zip \
       && unzip nomad.zip \
       && mv nomad /usr/local/bin/ \
       && rm nomad.zip
   
   ENTRYPOINT ["/bin/bash"]
   ```

6. **Create WordPress .drone.yml**
   ```yaml
   # docker/wordpress/.drone.yml
   kind: pipeline
   type: docker
   name: wordpress
   
   trigger:
     branch:
       - main
     event:
       - push
   
   steps:
     - name: build
       image: plugins/docker
       settings:
         repo: asdads6495/wordpress
         tags:
           - ${DRONE_COMMIT_SHA:0:8}
           - latest
         username:
           from_secret: dockerhub_username
         password:
           from_secret: dockerhub_password
         dockerfile: docker/wordpress/Dockerfile
         context: docker/wordpress
     
     - name: deploy
       image: asdads6495/nomad-deploy
       environment:
         NOMAD_ADDR: http://nomad.service.consul:4646
         NOMAD_TOKEN:
           from_secret: nomad_token
       commands:
         - |
           nomad job run \
             -var="docker_image_tag=${DRONE_COMMIT_SHA:0:8}" \
             -var-file=jobs/vars/dev.vars \
             jobs/wordpress.nomad.hcl
   
   ---
   kind: secret
   name: dockerhub_username
   get:
     path: secret/data/drone
     name: dockerhub_username
   
   ---
   kind: secret
   name: dockerhub_password
   get:
     path: secret/data/drone
     name: dockerhub_password
   
   ---
   kind: secret
   name: nomad_token
   get:
     path: secret/data/drone
     name: nomad_token
   ```

7. **Create Laravel .drone.yml**
   ```yaml
   # docker/laravel/.drone.yml
   kind: pipeline
   type: docker
   name: laravel
   
   trigger:
     branch:
       - main
     event:
       - push
   
   steps:
     - name: test
       image: php:8.2-cli
       commands:
         - composer install
         - php artisan test
     
     - name: build
       image: plugins/docker
       settings:
         repo: asdads6495/laravel
         tags:
           - ${DRONE_COMMIT_SHA:0:8}
           - latest
         username:
           from_secret: dockerhub_username
         password:
           from_secret: dockerhub_password
         dockerfile: docker/laravel/Dockerfile
         context: docker/laravel
     
     - name: deploy
       image: asdads6495/nomad-deploy
       environment:
         NOMAD_ADDR: http://nomad.service.consul:4646
         NOMAD_TOKEN:
           from_secret: nomad_token
       commands:
         - |
           nomad job run \
             -var="docker_image_tag=${DRONE_COMMIT_SHA:0:8}" \
             -var-file=jobs/vars/dev.vars \
             jobs/laravel.nomad.hcl
   
   ---
   kind: secret
   name: dockerhub_username
   get:
     path: secret/data/drone
     name: dockerhub_username
   
   ---
   kind: secret
   name: dockerhub_password
   get:
     path: secret/data/drone
     name: dockerhub_password
   
   ---
   kind: secret
   name: nomad_token
   get:
     path: secret/data/drone
     name: nomad_token
   ```

9. **Deploy Drone jobs**
   ```bash
   # Create host volume for Drone data
   nomad volume create drone-data.hcl
   
   # Deploy server
   nomad job run jobs/system/drone-server.nomad.hcl
   
   # Deploy vault extension (BEFORE runner)
   nomad job run jobs/system/drone-vault.nomad.hcl
   
   # Deploy runners
   nomad job run jobs/system/drone-runner.nomad.hcl
   ```

9. **Configure GitHub webhook**
   - Go to repo Settings → Webhooks
   - Add webhook:
     - Payload URL: `https://drone.your-domain.com/hook`
     - Content type: `application/json`
     - Events: Push, Pull Request

10. **Activate repos in Drone UI**
    - Go to `https://drone.your-domain.com`
    - Login with GitHub
    - Activate wordpress and laravel repos
    - Trigger test build

## Success Criteria

- [ ] Drone server running and accessible at `https://drone.hungpq.io.vn`
- [ ] Drone-vault extension running: `nomad job status drone-vault`
- [ ] GitHub OAuth login works
- [ ] Drone runners connected (check Drone UI → Runners)
- [ ] Push to main triggers build
- [ ] Build completes: test → build → push → deploy
- [ ] Vault secrets fetched successfully in pipeline
- [ ] New image deployed to Nomad automatically
- [ ] Rollback on failed health check (canary deployment)

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| GitHub webhook fails | Check Drone logs, verify network/firewall |
| Vault secrets unavailable | Ensure Drone policy exists, check token |
| Docker socket access | Runner needs privileged mode |
| Pipeline timeout | Increase runner capacity, optimize builds |
