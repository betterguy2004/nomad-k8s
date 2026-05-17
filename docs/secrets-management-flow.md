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
│  │ wordpress-      │                                            │
│  │ secrets         │──► CAN read secret/data/wordpress/*        │
│  │ policy          │                                            │
│  └─────────────────┘                                            │
│                                                                  │
│  ┌─────────────────┐                                            │
│  │ drone-secrets   │                                            │
│  │ policy          │──► CAN read secret/data/drone/*            │
│  └─────────────────┘                                            │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ nomad-workloads role (JWT auth)                          │    │
│  │   policies = ["wordpress-secrets", "drone-secrets"]      │    │
│  │   bound_audiences = ["vault.io"]                         │    │
│  │   user_claim = "nomad_job_id"                            │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### Nomad-Vault Integration (Workload Identity)

Nomad 2.x uses **Workload Identity** with JWT tokens instead of static Vault tokens.

```
┌─────────────────────────────────────────────────────────────────┐
│                  WORKLOAD IDENTITY FLOW                          │
│                                                                  │
│  Nomad Job Definition                                            │
│         │                                                        │
│         │  task "wordpress" {                                    │
│         │    vault { role = "nomad-workloads" }                  │
│         │  }                                                     │
│         │                                                        │
│         ▼                                                        │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Nomad Server                                             │    │
│  │                                                          │    │
│  │  1. Generates JWT token with claims:                     │    │
│  │     - aud: ["vault.io"]                                  │    │
│  │     - nomad_job_id: "wordpress"                          │    │
│  │     - nomad_namespace: "default"                         │    │
│  │     - nomad_task: "wordpress"                            │    │
│  │                                                          │    │
│  │  2. Signs JWT with Nomad's private key                   │    │
│  │     (JWKS available at /.well-known/jwks.json)           │    │
│  └──────────────────────────┬──────────────────────────────┘    │
│                             │                                    │
│                             ▼                                    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Vault JWT Auth (path: jwt-nomad)                         │    │
│  │                                                          │    │
│  │  1. Validates JWT signature via Nomad JWKS               │    │
│  │  2. Checks bound_audiences = "vault.io"                  │    │
│  │  3. Maps claims to token metadata                        │    │
│  │  4. Returns Vault token with assigned policies           │    │
│  └──────────────────────────┬──────────────────────────────┘    │
│                             │                                    │
│                             ▼                                    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Container Environment                                    │    │
│  │                                                          │    │
│  │  Vault token injected, templates rendered:               │    │
│  │  {{with secret "secret/data/wordpress/keys"}}            │    │
│  │  WORDPRESS_AUTH_KEY={{.Data.data.auth_key}}              │    │
│  │  {{end}}                                                 │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

**Benefits of Workload Identity:**
- No static Vault tokens stored in Nomad config
- Automatic token rotation via JWT TTL
- Fine-grained identity per task (job_id, namespace, task name in claims)

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
| WP Auth Keys | `secret/wordpress/keys` | WordPress | Static | Manual |
| WP DB Creds | `secret/wordpress/db` | WordPress | Static | Manual |
| Drone Server | `secret/drone/server` | Drone | Static | Manual |
| Nomad ACL Token | N/A | Admin only | N/A | After bootstrap |
| Vault Root Token | N/A | Admin only | N/A | After init |
| AWS KMS Key | AWS | Vault | N/A | AWS managed |

**Auth Method:** JWT (Workload Identity) at path `jwt-nomad`
**Role:** `nomad-workloads` (bound to audience `vault.io`)

---

## 8. Troubleshooting Commands

```bash
# Check Vault status
vault status

# List auth methods
vault auth list

# Check JWT auth config
vault read auth/jwt-nomad/config
vault read auth/jwt-nomad/role/nomad-workloads

# Test KV secrets
vault kv get secret/wordpress/keys
vault kv get secret/wordpress/db
vault kv get secret/drone/server

# Check Vault policies
vault policy list
vault policy read wordpress-secrets
vault policy read drone-secrets

# Check Nomad JWKS endpoint (for JWT validation)
curl http://localhost:4646/.well-known/jwks.json

# Debug Nomad job secrets
nomad alloc logs <alloc-id>
nomad alloc exec <alloc-id> env | grep -E "WORDPRESS_|DRONE_"

# Check Nomad ACL
export NOMAD_TOKEN=<bootstrap-token>
nomad acl token self
```

---

## References

- [Vault Database Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/databases)
- [Vault KV v2 Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2)
- [Nomad Vault Integration](https://developer.hashicorp.com/nomad/docs/integrations/vault-integration)
- [Consul Connect Intentions](https://developer.hashicorp.com/consul/docs/connect/intentions)
