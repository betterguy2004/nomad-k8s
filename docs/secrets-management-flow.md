# Secrets Management Flow

## Overview

Hệ thống sử dụng **HashiCorp Vault** làm central secrets manager với 2 loại secrets:
1. **Dynamic Secrets** - Database credentials tự động rotate
2. **Static Secrets** - API keys, tokens lưu trong KV store

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SECRETS FLOW                                    │
│                                                                              │
│  ┌─────────────┐         ┌─────────────────────────────────────────────┐    │
│  │   AWS KMS   │ ──────► │              VAULT CLUSTER                  │    │
│  │ (auto-unseal)│         │  ┌─────────────────┐ ┌─────────────────┐   │    │
│  └─────────────┘         │  │ Database Engine │ │   KV v2 Engine  │   │    │
│                          │  │                 │ │                 │   │    │
│                          │  │ roles/wordpress │ │ secret/wordpress│   │    │
│                          │  │ roles/laravel   │ │ secret/laravel  │   │    │
│                          │  │                 │ │ secret/drone    │   │    │
│                          │  └────────┬────────┘ └────────┬────────┘   │    │
│                          └───────────┼───────────────────┼────────────┘    │
│                                      │                   │                  │
│                          ┌───────────▼───────────────────▼───────────┐     │
│                          │            NOMAD CLUSTER                   │     │
│                          │                                            │     │
│                          │  ┌──────────────┐  ┌──────────────┐       │     │
│                          │  │  WordPress   │  │   Laravel    │       │     │
│                          │  │              │  │              │       │     │
│                          │  │ template {   │  │ template {   │       │     │
│                          │  │   secret ... │  │   secret ... │       │     │
│                          │  │ }            │  │ }            │       │     │
│                          │  └──────┬───────┘  └──────┬───────┘       │     │
│                          │         │                 │                │     │
│                          └─────────┼─────────────────┼────────────────┘     │
│                                    │                 │                      │
│                          ┌─────────▼─────────────────▼─────────┐           │
│                          │           RDS MySQL                  │           │
│                          │   (dynamic credentials từ Vault)     │           │
│                          └──────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. Vault Auto-Unseal (AWS KMS)

```
EC2 Instance Boot
       │
       ▼
┌──────────────────┐
│ Vault Service    │
│ Starts           │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐     ┌─────────────┐
│ Seal Check       │────►│  AWS KMS    │
│ (awskms seal)    │     │  Decrypt    │
└────────┬─────────┘     └─────────────┘
         │
         ▼
┌──────────────────┐
│ Vault Unsealed   │
│ Ready for use    │
└──────────────────┘
```

**Vault config:**
```hcl
seal "awskms" {
  region     = "us-west-1"
  kms_key_id = "alias/vault-unseal-dev"
}
```

**IAM Policy required:**
```json
{
  "Effect": "Allow",
  "Action": ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"],
  "Resource": "arn:aws:kms:us-west-1:*:key/*"
}
```

---

## 2. Dynamic Database Credentials

### Flow chi tiết

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    DYNAMIC DATABASE CREDENTIALS FLOW                     │
│                                                                          │
│  ┌─────────────┐                                                         │
│  │ Nomad Job   │                                                         │
│  │ Starts      │                                                         │
│  └──────┬──────┘                                                         │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ Nomad Template Block                                             │    │
│  │                                                                  │    │
│  │  template {                                                      │    │
│  │    data = <<EOF                                                  │    │
│  │    {{with secret "database/creds/wordpress"}}                    │    │
│  │    DB_USER={{.Data.username}}     ◄─── Dynamic username          │    │
│  │    DB_PASS={{.Data.password}}     ◄─── Dynamic password          │    │
│  │    {{end}}                                                       │    │
│  │    EOF                                                           │    │
│  │  }                                                               │    │
│  └──────────────────────────┬──────────────────────────────────────┘    │
│                             │                                            │
│                             │ 1. Request credentials                     │
│                             ▼                                            │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ Vault Database Secrets Engine                                    │    │
│  │                                                                  │    │
│  │  database/config/mysql ──► Connection to RDS                     │    │
│  │                                                                  │    │
│  │  database/roles/wordpress:                                       │    │
│  │    creation_statements = "CREATE USER '{{name}}'..."             │    │
│  │    default_ttl = "1h"                                            │    │
│  │    max_ttl = "24h"                                               │    │
│  └──────────────────────────┬──────────────────────────────────────┘    │
│                             │                                            │
│                             │ 2. Create user in MySQL                    │
│                             ▼                                            │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ RDS MySQL                                                        │    │
│  │                                                                  │    │
│  │  CREATE USER 'v-nomad-wordpre-abc123'@'%'                        │    │
│  │  IDENTIFIED BY 'random-password-xyz';                            │    │
│  │                                                                  │    │
│  │  GRANT ALL ON wordpress.* TO 'v-nomad-wordpre-abc123'@'%';       │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                             │                                            │
│                             │ 3. Return credentials                      │
│                             ▼                                            │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ Container Environment                                            │    │
│  │                                                                  │    │
│  │  DB_USER=v-nomad-wordpre-abc123                                  │    │
│  │  DB_PASS=random-password-xyz                                     │    │
│  │  (TTL: 1 hour, auto-renewed by Nomad)                            │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

### Credential Lifecycle

```
Time ──────────────────────────────────────────────────────────────────►

T=0          T=45min        T=1h           T=1h+          T=24h
 │              │             │              │               │
 ▼              ▼             ▼              ▼               │
┌────┐       ┌─────┐       ┌─────┐       ┌─────┐           │
│New │       │Renew│       │ TTL │       │ New │           │
│Cred│       │Lease│       │ End │       │Cred │           │
└────┘       └─────┘       └─────┘       └─────┘           │
                                                            │
                                             Max TTL ───────┘
                                             (forced rotation)

Nomad tự động:
1. Renew lease trước khi hết TTL (grace period)
2. Request new credentials nếu renew fail
3. Restart container với credentials mới
```

---

## 3. Static Secrets (KV v2)

### Flow chi tiết

```
┌─────────────────────────────────────────────────────────────────┐
│                    STATIC SECRETS FLOW (KV v2)                   │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Vault KV v2 Store                                          │  │
│  │                                                            │  │
│  │  secret/wordpress:                                         │  │
│  │    auth_key: "base64-random..."                            │  │
│  │    secure_auth_key: "base64-random..."                     │  │
│  │    s3_bucket: "nomad-media-xxx-dev"                        │  │
│  │    s3_region: "us-west-1"                                  │  │
│  │                                                            │  │
│  │  secret/laravel:                                           │  │
│  │    app_key: "base64-random..."                             │  │
│  │    s3_bucket: "nomad-media-xxx-dev"                        │  │
│  │                                                            │  │
│  │  secret/drone:                                             │  │
│  │    dockerhub_username: "xxx"                               │  │
│  │    dockerhub_password: "xxx"                               │  │
│  │    nomad_token: "xxx"                                      │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              │ Nomad template reads              │
│                              ▼                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Nomad Job Template                                         │  │
│  │                                                            │  │
│  │  {{with secret "secret/data/wordpress"}}                   │  │
│  │  WORDPRESS_AUTH_KEY={{.Data.data.auth_key}}                │  │
│  │  WP_OFFLOAD_MEDIA_BUCKET={{.Data.data.s3_bucket}}          │  │
│  │  {{end}}                                                   │  │
│  │                                                            │  │
│  │  NOTE: KV v2 path format: secret/data/<path>               │  │
│  │        Access data via: .Data.data.<key>                   │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. Vault Policies (Access Control)

### Policy Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      VAULT POLICIES                              │
│                                                                  │
│  ┌─────────────────┐                                            │
│  │ wordpress       │                                            │
│  │ policy          │                                            │
│  │                 │                                            │
│  │ path "database/ │──► CAN read database/creds/wordpress       │
│  │   creds/        │                                            │
│  │   wordpress"    │                                            │
│  │ { read }        │                                            │
│  │                 │                                            │
│  │ path "secret/   │──► CAN read secret/data/wordpress/*        │
│  │   data/         │                                            │
│  │   wordpress/*"  │                                            │
│  │ { read }        │──► CANNOT read secret/data/laravel/*       │
│  └─────────────────┘    CANNOT read database/creds/laravel      │
│                                                                  │
│  ┌─────────────────┐                                            │
│  │ laravel         │                                            │
│  │ policy          │──► CAN read database/creds/laravel         │
│  │ { similar }     │──► CAN read secret/data/laravel/*          │
│  └─────────────────┘                                            │
│                                                                  │
│  ┌─────────────────┐                                            │
│  │ drone           │                                            │
│  │ policy          │──► CAN read secret/data/drone/*            │
│  │ { read only }   │──► CANNOT read database/*                  │
│  └─────────────────┘                                            │
└─────────────────────────────────────────────────────────────────┘
```

### Nomad-Vault Integration

```
Nomad Job Definition
        │
        │  vault {
        │    policies = ["wordpress"]
        │  }
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│ Nomad Server                                                   │
│                                                                │
│  1. Nomad có Vault token với policy "nomad-server"             │
│  2. Nomad tạo child token với policy "wordpress" cho job       │
│  3. Child token được inject vào container                      │
│                                                                │
│  Token hierarchy:                                              │
│                                                                │
│  Vault Root Token (không dùng trong runtime)                   │
│        │                                                       │
│        ▼                                                       │
│  Nomad Server Token (policy: nomad-server)                     │
│        │                                                       │
│        ├──► WordPress Job Token (policy: wordpress)            │
│        │                                                       │
│        ├──► Laravel Job Token (policy: laravel)                │
│        │                                                       │
│        └──► Drone Job Token (policy: drone)                    │
└───────────────────────────────────────────────────────────────┘
```

---

## 5. Drone CI/CD Secrets Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    DRONE CI/CD SECRETS FLOW                      │
│                                                                  │
│  ┌─────────────────┐                                            │
│  │ .drone.yml      │                                            │
│  │                 │                                            │
│  │ kind: secret    │                                            │
│  │ name: docker_pw │                                            │
│  │ get:            │                                            │
│  │   path: secret/ │                                            │
│  │     data/drone  │                                            │
│  │   name: docker  │                                            │
│  │     hub_password│                                            │
│  └────────┬────────┘                                            │
│           │                                                      │
│           │ 1. Pipeline starts                                   │
│           ▼                                                      │
│  ┌─────────────────┐     ┌─────────────────┐                    │
│  │ Drone Server    │────►│ Vault           │                    │
│  │                 │     │                 │                    │
│  │ (Vault extension│     │ secret/data/    │                    │
│  │  enabled)       │◄────│ drone           │                    │
│  └────────┬────────┘     └─────────────────┘                    │
│           │                                                      │
│           │ 2. Inject secrets into step                          │
│           ▼                                                      │
│  ┌─────────────────┐                                            │
│  │ Drone Runner    │                                            │
│  │                 │                                            │
│  │ steps:          │                                            │
│  │   - name: build │                                            │
│  │     settings:   │                                            │
│  │       username: │                                            │
│  │         from_   │◄── Secret injected as env var              │
│  │         secret: │                                            │
│  │         docker_ │                                            │
│  │         hub_user│                                            │
│  └─────────────────┘                                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. Security Boundaries

```
┌─────────────────────────────────────────────────────────────────┐
│                      SECURITY BOUNDARIES                         │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ NETWORK LAYER (Consul Connect mTLS)                         ││
│  │                                                              ││
│  │  [nginx] ──mTLS──► [wordpress] ──mTLS──► [mysql]            ││
│  │              │                                               ││
│  │              └─mTLS──► [laravel] ──mTLS──► [mysql]          ││
│  │                                                              ││
│  │  Consul Intentions:                                          ││
│  │    nginx → wordpress [allow]                                 ││
│  │    nginx → laravel   [allow]                                 ││
│  │    * → *             [deny]                                  ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ APPLICATION LAYER (Vault Policies)                          ││
│  │                                                              ││
│  │  WordPress Pod:                                              ││
│  │    ✓ database/creds/wordpress                                ││
│  │    ✓ secret/data/wordpress/*                                 ││
│  │    ✗ database/creds/laravel                                  ││
│  │    ✗ secret/data/drone/*                                     ││
│  │                                                              ││
│  │  Laravel Pod:                                                ││
│  │    ✓ database/creds/laravel                                  ││
│  │    ✓ secret/data/laravel/*                                   ││
│  │    ✗ database/creds/wordpress                                ││
│  │    ✗ secret/data/drone/*                                     ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ INFRASTRUCTURE LAYER (AWS IAM)                              ││
│  │                                                              ││
│  │  EC2 Instance Role:                                          ││
│  │    ✓ kms:Decrypt (Vault auto-unseal)                         ││
│  │    ✓ ec2:DescribeInstances (Consul auto-join)                ││
│  │    ✓ s3:PutObject (media uploads)                            ││
│  │    ✗ rds:* (no direct RDS access)                            ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## 7. Secrets Inventory

| Secret Type | Path | Consumer | TTL | Rotation |
|-------------|------|----------|-----|----------|
| DB Creds (WP) | `database/creds/wordpress` | WordPress | 1h | Auto |
| DB Creds (Laravel) | `database/creds/laravel` | Laravel | 1h | Auto |
| WP Auth Keys | `secret/wordpress` | WordPress | Static | Manual |
| Laravel App Key | `secret/laravel` | Laravel | Static | Manual |
| DockerHub Creds | `secret/drone` | Drone CI | Static | Manual |
| Nomad Token | `secret/drone` | Drone CI | Static | Manual |
| Vault Root Token | N/A | Admin only | N/A | After init |
| AWS KMS Key | AWS | Vault | N/A | AWS managed |

---

## 8. Troubleshooting Commands

```bash
# Check Vault status
vault status

# List enabled secrets engines
vault secrets list

# Test database credentials
vault read database/creds/wordpress
vault read database/creds/laravel

# Test KV secrets
vault kv get secret/wordpress
vault kv get secret/laravel
vault kv get secret/drone

# Check Vault policies
vault policy list
vault policy read wordpress

# Check Consul intentions
consul intention list
consul intention check nginx wordpress

# Debug Nomad job secrets
nomad alloc logs <alloc-id>
nomad alloc exec <alloc-id> env | grep -E "DB_|APP_"

# Rotate database credentials manually
vault lease revoke -prefix database/creds/wordpress
```

---

## References

- [Vault Database Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/databases)
- [Vault KV v2 Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2)
- [Nomad Vault Integration](https://developer.hashicorp.com/nomad/docs/integrations/vault-integration)
- [Consul Connect Intentions](https://developer.hashicorp.com/consul/docs/connect/intentions)
