# System Architecture

Complete AWS infrastructure using HashiCorp stack for container orchestration, service discovery, and secrets management.

## High-Level Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AWS (us-west-1)                              │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │                    VPC (10.0.0.0/16)                        │    │
│  │                                                             │    │
│  │  ┌──────────────────────────────────────────────────────┐  │    │
│  │  │   PUBLIC SUBNET (10.0.1.0/24) - EC2 Cluster Nodes    │  │    │
│  │  │                                                       │  │    │
│  │  │  ┌────────┐  ┌────────┐  ┌────────┐                  │  │    │
│  │  │  │  Node  │  │  Node  │  │  Node  │                  │  │    │
│  │  │  │   1    │  │   2    │  │   3    │ (Nomad servers)  │  │    │
│  │  │  │ Public │  │ Public │  │ Public │ (Consul servers) │  │    │
│  │  │  │   IP   │  │   IP   │  │   IP   │ (Vault)          │  │    │
│  │  │  │ Nomad  │  │ Nomad  │  │ Nomad  │                  │  │    │
│  │  │  │Consul  │  │Consul  │  │Consul  │                  │  │    │
│  │  │  │Vault   │  │Vault   │  │Vault   │                  │  │    │
│  │  │  └────┬───┘  └────┬───┘  └────┬───┘                  │  │    │
│  │  │       │           │           │                       │  │    │
│  │  │       └───────────┼───────────┘ (Raft consensus)     │  │    │
│  │  │                   │             (gossip protocol)     │  │    │
│  │  │                   ▼                                   │  │    │
│  │  │          ┌──────────────────┐                        │  │    │
│  │  │          │  Nomad Jobs:     │                        │  │    │
│  │  │          │  ├─ WordPress    │                        │  │    │
│  │  │          │  ├─ Laravel      │                        │  │    │
│  │  │          │  ├─ Nginx LB     │                        │  │    │
│  │  │          │  └─ Drone CI/CD  │                        │  │    │
│  │  │          └──────────────────┘                        │  │    │
│  │  └──────────────────────────────────────────────────────┘  │    │
│  │                                                             │    │
│  │  ┌──────────────────────────────────────────────────────┐  │    │
│  │  │   PRIVATE SUBNET (10.0.2.0/24) - Data Tier           │  │    │
│  │  │  • RDS MySQL 8.0 (db.t3.micro)                       │  │    │
│  │  │  • No internet access (local VPC routing only)       │  │    │
│  │  └──────────────────────────────────────────────────────┘  │    │
│  │                                                             │    │
│  │  NOTE: No NAT Gateway - EC2 in public subnet with public   │    │
│  │        IPs for cost savings (~$32/month saved)             │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │      AWS SERVICES                                          │    │
│  │  • CloudFront CDN (S3 media delivery)                      │    │
│  │  • S3 (nomad-media-xxx-dev)                                │    │
│  │  • KMS (Vault auto-unseal)                                 │    │
│  │  • Route53 (DNS)                                           │    │
│  │  • IAM (instance roles)                                    │    │
│  └────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

## Infrastructure Layers

### 1. Network Layer (base-infra)

**VPC & Subnets**
- VPC: 10.0.0.0/16
- Public Subnet: 10.0.1.0/24 (EC2 cluster nodes with public IPs, Internet Gateway)
- Private Subnet: 10.0.2.0/24 (RDS only, no internet access)
- **No NAT Gateway** - cost optimization for dev/learning environment (~$32/month saved)

**Security Groups**
- `nomad-cluster-sg`: Internal cluster communication (8300-8302, 8500-8502, 4646)
- `rds-sg`: Only accepts MySQL from cluster SG (port 3306)
- `alb-sg`: Allows HTTP/HTTPS from internet (80, 443)

**Route53**
- `*.dev.nomad-k8s.internal`: Internal DNS for Consul services
- `example.com`: CloudFront alias for CDN

**KMS**
- `alias/vault-unseal-dev`: Encrypts Vault seal key, auto-decrypts on startup

### 2. Cluster Layer (cluster)

**EC2 Instances** (3 nodes, t3.medium, 2 vCPU, 4GB RAM)
- AMI: Custom Packer build (see next section)
- Auto-join via EC2 tags: `ConsulAutoJoin=auto-join`
- Each node runs:
  - **Nomad Server** (Raft consensus, job scheduler)
  - **Nomad Client** (task execution, resource management)
  - **Consul Server** (service catalog, health checks, Connect mesh)
  - **Vault Server** (secrets management, auto-unseal via KMS)

**IAM Roles**
- EC2 instance role allows:
  - `ec2:DescribeInstances` + `ec2:DescribeTags` (Consul auto-join)
  - `kms:Decrypt` (Vault auto-unseal)
  - `s3:GetObject` + `s3:PutObject` (application media storage)
  - CloudWatch logs

**Network Behavior**
- Cluster nodes communicate via private IPs (10.0.10.x, 10.0.11.x, 10.0.12.x)
- Raft consensus on port 8300 (TCP)
- Gossip protocol on ports 8301-8302 (TCP/UDP)
- gRPC on port 8502 (Connect proxy, xDS)
- HTTP API on port 8500

### 3. Packer AMI Build

**nomad-cluster.pkr.hcl** creates base image with:

**Pre-installed Software**
- Nomad + systemd service
- Consul + systemd service
- Vault + systemd service
- Docker daemon
- AWS CLI
- Consul Template (watches KV store)

**Pre-configured Files**
- `/opt/nomad/config/nomad.hcl` — Server + client config, Consul integration
- `/opt/consul/config/consul.hcl` — Server config, auto-join via AWS tags
- `/opt/vault/config/vault.hcl` — Server config, auto-unseal via KMS, Consul backend
- `/etc/systemd/system/nomad.service` — Auto-start on boot
- `/etc/systemd/system/consul.service` — Auto-start on boot
- `/etc/systemd/system/vault.service` — Auto-start on boot

**User Data Script** (runs after EC2 launch)
1. Starts Consul agent (discovers cluster via EC2 tags)
2. Starts Vault (auto-unseals via KMS)
3. Starts Nomad (joins cluster, becomes server)

### 4. Data Layer (data)

**RDS MySQL** (db.t3.micro, Single-AZ for dev)
- Endpoint: Stored in Consul KV at `rds/endpoint`
- Database: `wordpress` + `laravel` (separate schemas)
- Root user created by Terraform
- Vault dynamically creates role-based users:
  - `v-nomad-wordpress-*` (rotates hourly)
  - `v-nomad-laravel-*` (rotates hourly)

**S3 Buckets**
- `nomad-media-xxx-dev`: WordPress/Laravel media uploads
- `nomad-backups-xxx-dev`: RDS backups, application backups
- Objects encrypted at rest via KMS
- CloudFront caches `nomad-media-xxx-dev` for CDN delivery

### 5. CDN Layer (cdn)

**CloudFront Distribution**
- Origin: `nomad-media-xxx-dev.s3-us-west-1.amazonaws.com`
- Domain: `media.example.com` (CNAME via Route53)
- SSL/TLS: ACM certificate (auto-issued by Terraform)
- Cache behavior: 24-hour TTL for images, 1-hour for other assets
- Security: Restricts access via origin access identity (OAI)

---

## Nomad Jobs

### WordPress Service

**Job**: `jobs/wordpress.nomad.hcl`
- **Count**: 2 replicas (load balanced)
- **Driver**: Docker (`asdads6495/wordpress:latest`)
- **Port**: 9000 (FPM socket)
- **Resources**: 500 CPU, 512 MB memory
- **Vault Integration**: Retrieves dynamic MySQL creds + static auth keys
- **Service Registration**: Consul discovers as `wordpress.service.consul`
- **Health Check**: TCP on port 9000 every 10s

**Environment Variables**
```env
WORDPRESS_DB_HOST=<from-consul-kv-rds/endpoint>
WORDPRESS_DB_USER=<dynamic-cred-from-vault>
WORDPRESS_DB_PASSWORD=<dynamic-cred-from-vault>
WORDPRESS_DB_NAME=wordpress
WORDPRESS_AUTH_KEY=<from-vault-secret/wordpress>
WORDPRESS_SECURE_AUTH_KEY=<from-vault-secret/wordpress>
WP_OFFLOAD_MEDIA_BUCKET=nomad-media-xxx-dev
WP_OFFLOAD_MEDIA_REGION=us-west-1
```

### Laravel Service

**Job**: `jobs/laravel.nomad.hcl`
- **Count**: 2 replicas (load balanced)
- **Prestart Task**: Database migrations (`php artisan migrate --force`)
- **Driver**: Docker (`asdads6495/laravel:latest`)
- **Port**: 9000 (FPM socket)
- **Resources**: Main task 500 CPU / 512 MB, migrate task 200 CPU / 256 MB
- **Vault Integration**: Similar to WordPress (dynamic DB creds)
- **Service Registration**: `laravel.service.consul`

### Nginx Load Balancer

**Job**: `jobs/system/nginx-lb.nomad.hcl`
- **Count**: 1 (single entry point)
- **Port**: 80 (HTTP), 443 (HTTPS)
- **Config**: Consul Template renders upstream blocks dynamically
- **Upstreams**:
  - `upstream wordpress { {{ range service "wordpress" }} server {{ .Address }}:{{ .Port }}; {{ end }} }`
  - `upstream laravel { {{ range service "laravel" }} server {{ .Address }}:{{ .Port }}; {{ end }} }`
- **Auto-Reload**: Watches Consul for service changes, reloads Nginx via SIGHUP

### Drone CI/CD System

**Server** (`jobs/system/drone-server.nomad.hcl`)
- Orchestrates CI/CD pipelines
- Stores config in Consul KV
- Integrates with Vault for secret injection

**Runner** (`jobs/system/drone-runner.nomad.hcl`)
- Executes jobs in Docker containers
- Pulls Docker credentials from Vault
- Reports back to Drone Server

**Vault Extension** (`jobs/system/drone-vault.nomad.hcl`)
- Bridges Drone pipelines to Vault
- Allows `.drone.yml` to reference `secret/data/drone`

---

## Service Discovery & Mesh

### Consul Service Discovery

1. **Registration**: When Nomad starts a job, it registers the service with local Consul agent
   ```hcl
   service {
     name = "wordpress"
     port = "fpm"
     check {
       type     = "tcp"
       port     = "fpm"
       interval = "10s"
       timeout  = "2s"
     }
   }
   ```

2. **Discovery**: Services query Consul DNS or API
   ```bash
   dig @127.0.0.1 -p 8600 wordpress.service.consul
   # Returns: 10.0.10.5, 10.0.10.6 (healthy instances)
   ```

3. **Dynamic Load Balancing**: Nginx uses Consul Template to auto-generate config
   ```nginx
   upstream wordpress {
     server 10.0.10.5:9000;
     server 10.0.10.6:9000;
   }
   ```
   Reloads when services change.

### Consul Connect (Service Mesh)

**mTLS Encryption**
- Envoy sidecars on each service (auto-injected by Nomad)
- Certificates issued by Consul CA (SPIFFE-compatible)
- Automatic rotation every 72 hours

**Intentions (Access Control)**
- Default: DENY ALL
- Explicit allow rules:
  - `nginx → wordpress`: allowed
  - `nginx → laravel`: allowed
  - `wordpress → mysql`: allowed (via Nomad connect upstream)
  - `laravel → mysql`: allowed (via Nomad connect upstream)
  - `drone-runner → nomad`: allowed

Example job config with Connect:
```hcl
service {
  name = "wordpress"
  port = "fpm"
  connect {
    sidecar_service {
      proxy {
        upstreams {
          destination_name = "mysql"
          local_bind_port  = 3306
        }
      }
    }
  }
}
```

The Envoy sidecar:
1. Listens on localhost:3306 in the container
2. Routes traffic to `mysql.service.consul` via mTLS
3. Checks intentions with Consul before allowing traffic

---

## Secrets Management

### Vault Architecture

**Storage**: Consul KV backend (distributed across 3 Consul servers)
- High availability with automatic failover
- Raft consensus ensures consistency
- Data path: `vault/`

**Auto-Unseal via AWS KMS**
```hcl
seal "awskms" {
  region     = "us-west-1"
  kms_key_id = "alias/vault-unseal-dev"
}
```
On startup, Vault automatically:
1. Decrypts seal key from AWS KMS
2. Unseals without manual intervention
3. Becomes ready for requests

### Secrets Engines

**1. Database Engine** (dynamic credentials)
- Config: Connection to RDS MySQL
- Roles:
  - `database/roles/wordpress` — Creates/destroys users on-demand, TTL 1h
  - `database/roles/laravel` — Same pattern
- Nomad requests: `vault read database/creds/wordpress`
- Returns: Username + password (rotated automatically)

**2. KV v2 Engine** (static secrets)
- Paths:
  - `secret/wordpress` — Auth keys, S3 bucket settings
  - `secret/laravel` — App key, S3 settings
  - `secret/drone` — Docker credentials, Nomad token
- Nomad requests: `vault kv get secret/wordpress`
- Returns: All key-value pairs in one shot

### Vault Policies

Example `wordpress` policy:
```hcl
path "database/creds/wordpress" {
  capabilities = ["read"]
}

path "secret/data/wordpress/*" {
  capabilities = ["read"]
}
```

Only the WordPress job can access these paths. Laravel job has separate policy, cannot read WordPress secrets.

### Nomad-Vault Integration

1. **Job Definition** includes Vault policy:
   ```hcl
   vault {
     policies = ["wordpress"]
   }
   ```

2. **Nomad Server** (has `nomad-server` policy):
   - Creates child token with `wordpress` policy
   - Injects token into container at `$VAULT_TOKEN`

3. **Template Blocks** in job use Vault:
   ```hcl
   template {
     data = <<EOF
   {{with secret "database/creds/wordpress"}}
   DB_USER={{.Data.username}}
   DB_PASSWORD={{.Data.password}}
   {{end}}
     EOF
     destination = "secrets/env"
     env         = true
   }
   ```

4. **Nomad Agent** (in allocations):
   - Watches lease TTL
   - Renews before expiry
   - Restarts task if renewal fails

---

## Deployment Flow

```
1. Developer commits code
   └─ .drone.yml triggers build

2. Drone CI (Docker runner)
   ├─ Pulls Docker image from DockerHub
   ├─ Gets secrets from Vault (via drone-vault bridge)
   ├─ Builds & pushes to asdads6495/wordpress:latest
   └─ Notifies Nomad to re-run job

3. Nomad Job Update
   ├─ Scheduler places 2 WordPress tasks
   ├─ Pulls image from DockerHub
   ├─ Nomad template injects Vault secrets
   ├─ Registers with Consul
   ├─ Health checks pass
   └─ Traffic routed via Nginx

4. Nginx Load Balancer
   ├─ Watches Consul for changes
   ├─ Discovers 2 healthy WordPress instances
   ├─ Routes requests with round-robin
   └─ mTLS connects to WordPress via Envoy sidecar

5. WordPress Container
   ├─ Connects to MySQL (dynamic credentials auto-rotated)
   ├─ Accesses S3 media via WordPress plugin
   ├─ CloudFront caches S3 objects
   └─ Logs to CloudWatch
```

---

## Disaster Recovery

### Backup Strategy

- **Database**: RDS automated backups (7-day retention)
- **Secrets**: Consul KV snapshots (Vault data) to S3
- **Application Data**: S3 versioning + lifecycle policies

### High Availability

- **Nomad**: 3-node Raft cluster, survives 1 node loss
- **Consul**: 3-node Raft cluster, survives 1 node loss
- **Vault**: HA via Consul backend, survives 1 node loss
- **RDS**: Single-AZ (dev), can upgrade to Multi-AZ
- **Jobs**: Multi-replica (WordPress/Laravel = 2 each), auto-replace on failure

### Scaling

**Horizontal**
- Add EC2 nodes: Terraform + Packer → auto-join cluster
- Job replicas: Increase `count` in `.nomad.hcl` → Nomad schedules automatically
- RDS: Upgrade instance class via Terraform
- S3: Unlimited capacity (serverless)

**Vertical**
- Node CPU/Memory: Resize EC2 instance type
- RDS: Upgrade to db.t3.small/medium

---

## Key Files Reference

| Path | Purpose |
|------|---------|
| `infra/environments/dev/terragrunt.hcl` | Terragrunt root config |
| `infra/stacks/base-infra/vpc.tf` | VPC + subnets + security groups |
| `infra/stacks/cluster/ec2.tf` | EC2 instance definitions |
| `infra/stacks/data/rds.tf` | RDS MySQL database |
| `infra/stacks/data/s3.tf` | S3 buckets |
| `infra/stacks/cdn/cloudfront.tf` | CloudFront distribution |
| `infra/packer/nomad-cluster.pkr.hcl` | AMI build with HashiStack |
| `infra/shared/config/nomad.hcl` | Nomad server + client config |
| `infra/shared/config/consul.hcl` | Consul server config |
| `infra/shared/config/vault.hcl` | Vault server config |
| `jobs/wordpress.nomad.hcl` | WordPress job definition |
| `jobs/laravel.nomad.hcl` | Laravel job definition |
| `jobs/system/nginx-lb.nomad.hcl` | Nginx load balancer |
| `vault/init-vault.sh` | Vault initialization script |
| `docs/consul-role-overview.md` | Detailed Consul architecture |
| `docs/secrets-management-flow.md` | Detailed Vault architecture |

---

See also: [Deployment Guide](./deployment-guide.md)
