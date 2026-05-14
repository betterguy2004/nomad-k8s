---
phase: 5
title: "HashiCorp Configuration"
status: complete
priority: P1
effort: "2h"
dependencies: [4]
---

# Phase 5: HashiCorp Configuration

## Overview

Initialize Vault cluster, configure database secrets engine for MySQL dynamic credentials, set up Consul Connect intentions for service mesh mTLS.

## Requirements

**Functional:**
- Vault initialized and unsealed (auto-unseal via KMS)
- Database secrets engine with WordPress and Laravel roles
- Vault policies for each application
- Consul Connect intentions for allowed service communication

**Non-functional:**
- Root token stored securely (not in code)
- Policies follow least-privilege principle

## Architecture

```
Vault Secrets Flow:
┌─────────────────────────────────────────────────┐
│ Vault Cluster (HA via Consul)                   │
│  ┌───────────────────────────────────────────┐  │
│  │ Database Secrets Engine                   │  │
│  │  └─ config/mysql (connection)             │  │
│  │  └─ roles/wordpress (dynamic creds)       │  │
│  │  └─ roles/laravel (dynamic creds)         │  │
│  └───────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────┐  │
│  │ KV v2 Secrets Engine                      │  │
│  │  └─ secret/drone (DockerHub, Nomad token) │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘

Consul Connect Intentions:
nginx      → wordpress  [allow]
nginx      → laravel    [allow]
wordpress  → mysql      [allow]  (via Vault dynamic creds)
laravel    → mysql      [allow]  (via Vault dynamic creds)
drone-runner → nomad    [allow]
* → *                   [deny]   (default)
```

## Related Code Files

**Create:**
- `vault/policies/wordpress.hcl`
- `vault/policies/laravel.hcl`
- `vault/policies/drone.hcl`
- `vault/setup/init-vault.sh`
- `vault/setup/configure-database-secrets.sh`
- `vault/setup/configure-kv-secrets.sh`
- `vault/setup/configure-consul-intentions.sh`

## Implementation Steps

1. **Create Vault policies**

   ```hcl
   # vault/policies/wordpress.hcl
   path "database/creds/wordpress" {
     capabilities = ["read"]
   }
   
   path "secret/data/wordpress/*" {
     capabilities = ["read"]
   }
   ```

   ```hcl
   # vault/policies/laravel.hcl
   path "database/creds/laravel" {
     capabilities = ["read"]
   }
   
   path "secret/data/laravel/*" {
     capabilities = ["read"]
   }
   ```

   ```hcl
   # vault/policies/drone.hcl
   path "secret/data/drone/*" {
     capabilities = ["read"]
   }
   ```

2. **Create Vault init script**
   ```bash
   #!/bin/bash
   # vault/setup/init-vault.sh
   set -e
   
   export VAULT_ADDR="http://127.0.0.1:8200"
   
   # Check if already initialized
   if vault status | grep -q "Initialized.*true"; then
     echo "Vault already initialized"
     exit 0
   fi
   
   # Initialize (auto-unseal handles unseal)
   vault operator init -key-shares=1 -key-threshold=1 \
     -format=json > /tmp/vault-init.json
   
   echo "=== SAVE THESE SECURELY ==="
   cat /tmp/vault-init.json
   echo "==========================="
   
   # Wait for auto-unseal
   sleep 5
   
   # Login with root token
   ROOT_TOKEN=$(jq -r '.root_token' /tmp/vault-init.json)
   vault login $ROOT_TOKEN
   
   echo "Vault initialized and logged in"
   ```

3. **Create database secrets configuration**
   ```bash
   #!/bin/bash
   # vault/setup/configure-database-secrets.sh
   set -e
   
   export VAULT_ADDR="http://127.0.0.1:8200"
   
   # Get RDS info from Secrets Manager or pass as args
   RDS_HOST="${1:-mysql.example.com}"
   RDS_PORT="${2:-3306}"
   RDS_ADMIN_USER="${3:-admin}"
   RDS_ADMIN_PASS="${4}"
   
   # Enable database secrets engine
   vault secrets enable -path=database database || true
   
   # Configure MySQL connection
   vault write database/config/mysql \
     plugin_name=mysql-database-plugin \
     connection_url="{{username}}:{{password}}@tcp(${RDS_HOST}:${RDS_PORT})/" \
     allowed_roles="wordpress,laravel" \
     username="${RDS_ADMIN_USER}" \
     password="${RDS_ADMIN_PASS}"
   
   # Create WordPress role
   vault write database/roles/wordpress \
     db_name=mysql \
     creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT ALL ON wordpress.* TO '{{name}}'@'%';" \
     default_ttl="1h" \
     max_ttl="24h"
   
   # Create Laravel role
   vault write database/roles/laravel \
     db_name=mysql \
     creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT ALL ON laravel.* TO '{{name}}'@'%';" \
     default_ttl="1h" \
     max_ttl="24h"
   
   # Create databases
   mysql -h ${RDS_HOST} -u ${RDS_ADMIN_USER} -p${RDS_ADMIN_PASS} <<EOF
   CREATE DATABASE IF NOT EXISTS wordpress;
   CREATE DATABASE IF NOT EXISTS laravel;
   EOF
   
   echo "Database secrets engine configured"
   ```

4. **Create KV secrets configuration**
   ```bash
   #!/bin/bash
   # vault/setup/configure-kv-secrets.sh
   set -e
   
   export VAULT_ADDR="http://127.0.0.1:8200"
   
   # Enable KV v2
   vault secrets enable -path=secret -version=2 kv || true
   
   # Store Drone secrets (replace with actual values)
   vault kv put secret/drone \
     dockerhub_username="${DOCKERHUB_USER}" \
     dockerhub_password="${DOCKERHUB_PASS}" \
     nomad_token="${NOMAD_TOKEN}"
   
   # Store WordPress secrets
   vault kv put secret/wordpress \
     auth_key="$(openssl rand -base64 32)" \
     secure_auth_key="$(openssl rand -base64 32)" \
     s3_bucket="${S3_BUCKET}" \
     s3_region="us-west-1"  # Primary region
   
   # Store Laravel secrets
   vault kv put secret/laravel \
     app_key="$(openssl rand -base64 32)" \
     s3_bucket="${S3_BUCKET}" \
     s3_region="us-west-1"  # Primary region
   
   # Apply policies
   vault policy write wordpress vault/policies/wordpress.hcl
   vault policy write laravel vault/policies/laravel.hcl
   vault policy write drone vault/policies/drone.hcl
   
   echo "KV secrets and policies configured"
   ```

5. **Create Consul intentions configuration** (using config entries - recommended)
   ```bash
   #!/bin/bash
   # vault/setup/configure-consul-intentions.sh
   set -e
   
   # Create intentions via config entries (replaces deprecated CLI)
   cat <<EOF | consul config write -
   Kind = "service-intentions"
   Name = "*"
   Sources = [
     {
       Name   = "*"
       Action = "deny"
     }
   ]
   EOF
   
   cat <<EOF | consul config write -
   Kind = "service-intentions"
   Name = "wordpress"
   Sources = [
     {
       Name   = "nginx"
       Action = "allow"
     }
   ]
   EOF
   
   cat <<EOF | consul config write -
   Kind = "service-intentions"
   Name = "laravel"
   Sources = [
     {
       Name   = "nginx"
       Action = "allow"
     }
   ]
   EOF
   
   cat <<EOF | consul config write -
   Kind = "service-intentions"
   Name = "mysql"
   Sources = [
     {
       Name   = "wordpress"
       Action = "allow"
     },
     {
       Name   = "laravel"
       Action = "allow"
     }
   ]
   EOF
   
   cat <<EOF | consul config write -
   Kind = "service-intentions"
   Name = "nomad"
   Sources = [
     {
       Name   = "drone-runner"
       Action = "allow"
     }
   ]
   EOF
   
   echo "Consul intentions configured via config entries"
   ```

6. **Run configuration scripts (in order)**
   ```bash
   # SSH to one of the nodes
   ssh -i key.pem ec2-user@node-1
   
   # 1. Initialize Vault
   ./vault/setup/init-vault.sh
   
   # 2. Configure database secrets
   ./vault/setup/configure-database-secrets.sh \
     mysql.private-subnet.local 3306 admin "$MASTER_PASS"
   
   # 3. Configure KV secrets
   export DOCKERHUB_USER="your-user"
   export DOCKERHUB_PASS="your-pass"
   export S3_BUCKET="nomad-media-xxx-dev"
   export AWS_REGION="us-east-1"
   ./vault/setup/configure-kv-secrets.sh
   
   # 4. Configure Consul intentions
   ./vault/setup/configure-consul-intentions.sh
   ```

7. **Verify configuration**
   ```bash
   # Test database credentials
   vault read database/creds/wordpress
   vault read database/creds/laravel
   
   # Test KV secrets
   vault kv get secret/drone
   
   # Check Consul intentions
   consul intention list
   
   # Check Consul Connect
   consul connect ca get-config
   ```

## Success Criteria

- [ ] Vault initialized and auto-unseals on restart
- [ ] `vault read database/creds/wordpress` returns valid MySQL creds
- [ ] `vault read database/creds/laravel` returns valid MySQL creds
- [ ] `vault kv get secret/drone` returns DockerHub + Nomad token
- [ ] Consul intentions show allow/deny rules
- [ ] Consul Connect CA is bootstrapped

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Root token exposure | Store in password manager immediately after init |
| Database secrets rotation failure | Monitor Vault audit logs |
| Consul intention blocks legitimate traffic | Test with `consul intention check` before production |
