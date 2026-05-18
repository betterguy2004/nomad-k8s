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

Policies are created during bootstrap and assigned at the **job group level**:

```
┌─────────────────────────────────────────────────────────────────┐
│                      VAULT POLICIES                              │
│                                                                  │
│  ┌─────────────────┐                                            │
│  │ wordpress       │──► CAN read database/creds/wordpress       │
│  │ policy          │──► CAN read secret/data/wordpress/*        │
│  └─────────────────┘                                            │
│                                                                  │
│  ┌─────────────────┐                                            │
│  │ laravel         │──► CAN read database/creds/laravel         │
│  │ policy          │──► CAN read secret/data/laravel/*          │
│  └─────────────────┘                                            │
│                                                                  │
│  ┌─────────────────┐                                            │
│  │ drone           │──► CAN read secret/data/drone/*            │
│  │ policy          │                                            │
│  └─────────────────┘                                            │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ nomad-workloads role (JWT auth)                          │    │
│  │   token_policies = ["wordpress", "laravel", "drone"]     │    │
│  │   bound_audiences = ["vault.io"]                         │    │
│  │   user_claim = "/nomad_job_id"                           │    │
│  │   token_period = "30m" (auto-renew)                       │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### Creation & Deployment

Policies are created by `vault/setup/bootstrap-all.sh`:
1. Loads policy definitions from `vault/policies/*.hcl`
2. Applies to Vault cluster
3. Job groups reference policies by name:
   ```hcl
   group "wordpress" {
     vault {
       policies = ["wordpress"]
     }
   }
   ```

### Nomad-Vault Integration (Workload Identity)

Nomad uses **Workload Identity** with JWT tokens instead of static Vault tokens. Policies are assigned at the **group level**.

```
┌─────────────────────────────────────────────────────────────────┐
│                  WORKLOAD IDENTITY FLOW                          │
│                                                                  │
│  Nomad Job Group Definition                                      │
│         │                                                        │
│         │  group "wordpress" {                                   │
│         │    vault {                                             │
│         │      policies = ["wordpress"]  ◄─ Group policy         │
│         │    }                                                   │
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
│  │     - nomad_group: "wordpress"                           │    │
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
│  │  3. Maps user_claim (/nomad_job_id) to identity         │    │
│  │  4. Looks up role "nomad-workloads"                      │    │
│  │  5. Assigns policies: wordpress/laravel/drone (allowed)  │    │
│  │  6. Returns Vault token with group policies              │    │
│  │  7. Token auto-renews via period = "30m"                 │    │
│  └──────────────────────────┬──────────────────────────────┘    │
│                             │                                    │
│                             ▼                                    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Container Tasks (All in group inherit policy)            │    │
│  │                                                          │    │
│  │  Vault token injected, templates rendered:               │    │
│  │  {{with secret "secret/data/wordpress/keys"}}            │    │
│  │  WORDPRESS_AUTH_KEY={{.Data.data.auth_key}}              │    │
│  │  {{end}}                                                 │    │
│  │  {{with secret "database/creds/wordpress"}}              │    │
│  │  DB_USER={{.Data.username}}  (auto-renewed by Nomad)    │    │
│  │  {{end}}                                                 │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

**Benefits of Group-Level Policies:**
- All tasks in group share same Vault access
- Policy enforced at group, not per-task
- Simpler configuration, consistent access control
- JWT auto-renewal (30m period) prevents token expiry
- Fine-grained identity via job_id and namespace in claims

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

| Secret Type | Path | Engine | Consumer | TTL | Rotation |
|-------------|------|--------|----------|-----|----------|
| WordPress auth keys | `secret/wordpress/keys` | KV v2 | WordPress | ∞ | Manual (via bootstrap) |
| WordPress DB creds | `database/creds/wordpress` | Database | WordPress | 1h | Auto-renewed by Nomad |
| Laravel app key | `secret/laravel` | KV v2 | Laravel | ∞ | Manual (via bootstrap) |
| Laravel DB creds | `database/creds/laravel` | Database | Laravel | 1h | Auto-renewed by Nomad |
| Drone server config | `secret/drone/server` | KV v2 | Drone Server | ∞ | Manual |
| Drone runner config | `secret/drone/runner` | KV v2 | Drone Runner | ∞ | Manual |
| Drone-Vault token | `secret/drone/vault-extension` | KV v2 | Drone Vault | ∞ | Manual (730h period) |
| Nomad ACL token | `secret/nomad/bootstrap` | KV v2 | Admins | ∞ | After bootstrap |
| Vault root token | (env var) | N/A | One-time init | ∞ | After init |
| AWS KMS key | AWS | KMS | Vault | N/A | AWS managed |

**Auth Method:** JWT (Workload Identity) at path `jwt-nomad`
**Role:** `nomad-workloads` (group policies assigned via `vault { policies = [...] }`)
**Token TTL:** 30m with period renewal (auto-renews)

---

## 8. Setup & Troubleshooting

### Initial Setup

One-time bootstrap configures all secrets and policies:

```bash
cd vault/setup

# Set required environment variables
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=<vault-root-token>
export RDS_HOST=<rds-endpoint>
export RDS_ADMIN_PASS=<rds-password>
export GITHUB_CLIENT_ID=<github-oauth-id>
export GITHUB_CLIENT_SECRET=<github-oauth-secret>

# Run bootstrap (idempotent)
./bootstrap-all.sh
```

### Verification Commands

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
vault kv get secret/laravel
vault kv get secret/drone/server

# Test database roles (generates dynamic creds)
vault read database/creds/wordpress
vault read database/creds/laravel

# Check Vault policies
vault policy list
vault policy read wordpress
vault policy read laravel
vault policy read drone

# Check Nomad JWKS endpoint (for JWT validation)
curl http://localhost:4646/.well-known/jwks.json

# Debug Nomad job secrets
nomad alloc logs <alloc-id>
nomad alloc exec <alloc-id> env | grep -E "DB_|WORDPRESS_|DRONE_"

# Check Nomad ACL
export NOMAD_TOKEN=$(vault kv get -field=token secret/nomad/bootstrap)
nomad acl token self
```

### Troubleshooting

**Job fails: "permission denied" accessing secret**
```bash
# Check group has correct policy assigned
nomad job inspect <job> | grep -A 5 "vault"

# Verify policy exists
vault policy read <policy-name>

# Check JWT role has policy in allowed_policies
vault read auth/jwt-nomad/role/nomad-workloads
```

**Database credentials fail**
```bash
# Verify database config
vault read database/config/mysql

# Test role directly
vault read database/creds/wordpress

# Check role TTL/max_ttl
vault read database/roles/wordpress
```

---

## References

- [Vault Database Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/databases)
- [Vault KV v2 Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2)
- [Nomad Vault Integration](https://developer.hashicorp.com/nomad/docs/integrations/vault-integration)
- [Consul Connect Intentions](https://developer.hashicorp.com/consul/docs/connect/intentions)
