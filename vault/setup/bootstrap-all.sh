#!/bin/bash
# =============================================================================
# BOOTSTRAP ALL - One-time cluster initialization script
# =============================================================================
# Usage: Run this script ONCE after fresh cluster deployment
#        ./bootstrap-all.sh
#
# Prerequisites:
#   - Vault initialized and unsealed (KMS auto-unseal)
#   - VAULT_TOKEN set (root token from init)
#   - Consul cluster healthy
#   - Nomad cluster healthy
#   - RDS MySQL accessible
# =============================================================================
set -e

# =============================================================================
# CONFIGURATION - EDIT THESE VALUES FOR YOUR ENVIRONMENT
# =============================================================================

# Vault
export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-hvs.XXXXXXXXXXXXX}"  # Root token from vault init

# RDS MySQL
RDS_HOST="${RDS_HOST:-your-rds-endpoint.us-west-1.rds.amazonaws.com}"
RDS_PORT="3306"
RDS_ADMIN_USER="admin"
RDS_ADMIN_PASS="${RDS_ADMIN_PASS:-your-rds-password}"

# Docker Hub (for Drone CI)
DOCKERHUB_USER="${DOCKERHUB_USER:-your-dockerhub-username}"
DOCKERHUB_PASS="${DOCKERHUB_PASS:-your-dockerhub-password}"

# GitHub OAuth (for Drone CI) - REQUIRED, no defaults
GITHUB_CLIENT_ID="${GITHUB_CLIENT_ID:?ERROR: Set GITHUB_CLIENT_ID env var}"
GITHUB_CLIENT_SECRET="${GITHUB_CLIENT_SECRET:?ERROR: Set GITHUB_CLIENT_SECRET env var}"

# S3 Bucket (for WordPress/Laravel media)
S3_BUCKET="${S3_BUCKET:-your-s3-bucket}"
S3_REGION="${S3_REGION:-us-west-1}"

# Nomad
NOMAD_ADDR="${NOMAD_ADDR:-http://127.0.0.1:4646}"

# =============================================================================
# SCRIPT DIR
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "Starting cluster bootstrap..."
echo "VAULT_ADDR: $VAULT_ADDR"
echo "RDS_HOST: $RDS_HOST"
echo "=============================================="

# =============================================================================
# 1. VAULT: Enable secrets engines
# =============================================================================
echo ""
echo "[1/8] Enabling Vault secrets engines..."

vault secrets enable -path=secret -version=2 kv 2>/dev/null || echo "KV engine already enabled"
vault secrets enable -path=database database 2>/dev/null || echo "Database engine already enabled"

# =============================================================================
# 2. VAULT: Configure KV secrets
# =============================================================================
echo ""
echo "[2/8] Configuring KV secrets..."

# WordPress secrets (generate random keys) - lowercase to match template expectations
vault kv put secret/wordpress/keys \
  auth_key="$(openssl rand -base64 64)" \
  secure_auth_key="$(openssl rand -base64 64)" \
  logged_in_key="$(openssl rand -base64 64)" \
  nonce_key="$(openssl rand -base64 64)" \
  auth_salt="$(openssl rand -base64 64)" \
  secure_auth_salt="$(openssl rand -base64 64)" \
  logged_in_salt="$(openssl rand -base64 64)" \
  nonce_salt="$(openssl rand -base64 64)"

vault kv put secret/wordpress/db \
  host="$RDS_HOST" \
  name="wordpress" \
  user="wp_user" \
  password="$(openssl rand -base64 24)"

# Laravel secrets
vault kv put secret/laravel \
  app_key="base64:$(openssl rand -base64 32)" \
  s3_bucket="$S3_BUCKET" \
  s3_region="$S3_REGION"

# Drone secrets - server config (GitHub OAuth for authentication)
vault kv put secret/drone/server \
  github_client_id="$GITHUB_CLIENT_ID" \
  github_client_secret="$GITHUB_CLIENT_SECRET" \
  rpc_secret="$(openssl rand -hex 16)"

# Drone secrets - runner config (Docker Hub for builds)
vault kv put secret/drone/runner \
  dockerhub_username="$DOCKERHUB_USER" \
  dockerhub_password="$DOCKERHUB_PASS" \
  nomad_token="placeholder"

echo "KV secrets configured"

# =============================================================================
# 3. VAULT: Configure database secrets engine
# =============================================================================
echo ""
echo "[3/8] Configuring database secrets engine..."

vault write database/config/mysql \
  plugin_name=mysql-database-plugin \
  connection_url="{{username}}:{{password}}@tcp(${RDS_HOST}:${RDS_PORT})/" \
  allowed_roles="wordpress,laravel" \
  username="${RDS_ADMIN_USER}" \
  password="${RDS_ADMIN_PASS}"

vault write database/roles/wordpress \
  db_name=mysql \
  creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT ALL ON wordpress.* TO '{{name}}'@'%';" \
  default_ttl="1h" \
  max_ttl="24h"

vault write database/roles/laravel \
  db_name=mysql \
  creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT ALL ON laravel.* TO '{{name}}'@'%';" \
  default_ttl="1h" \
  max_ttl="24h"

echo "Database secrets engine configured"

# =============================================================================
# 4. VAULT: Apply policies
# =============================================================================
echo ""
echo "[4/8] Applying Vault policies..."

vault policy write wordpress "${VAULT_DIR}/policies/wordpress.hcl"
vault policy write laravel "${VAULT_DIR}/policies/laravel.hcl"
vault policy write drone "${VAULT_DIR}/policies/drone.hcl"

echo "Policies applied"

# Create a token for drone-vault extension (long-lived, used by drone-vault to proxy secrets)
DRONE_VAULT_TOKEN=$(vault token create -policy=drone -period=720h -format=json | jq -r '.auth.client_token')
vault kv put secret/drone/vault-extension token="$DRONE_VAULT_TOKEN"
echo "Drone-vault token created and stored"

# =============================================================================
# 5. VAULT: Configure JWT auth for Nomad workload identity
# =============================================================================
echo ""
echo "[5/8] Configuring JWT auth for Nomad..."

vault auth enable -path=jwt-nomad jwt 2>/dev/null || echo "JWT auth already enabled"

# Get Nomad JWKS URL (assumes Nomad running locally)
NOMAD_JWKS_URL="${NOMAD_ADDR}/.well-known/jwks.json"

vault write auth/jwt-nomad/config \
  jwks_url="$NOMAD_JWKS_URL" \
  jwt_supported_algs="RS256" \
  default_role="nomad-workloads"

vault write auth/jwt-nomad/role/nomad-workloads \
  role_type="jwt" \
  bound_audiences="vault.io" \
  user_claim="/nomad_job_id" \
  user_claim_json_pointer=true \
  claim_mappings="nomad_namespace=nomad_namespace" \
  claim_mappings="nomad_job_id=nomad_job_id" \
  token_type="service" \
  token_policies="default" \
  allowed_policies="wordpress,laravel,drone" \
  token_period="30m" \
  token_ttl="30m"

echo "JWT auth configured"

# =============================================================================
# 6. CONSUL: Write KV entries
# =============================================================================
echo ""
echo "[6/8] Writing Consul KV entries..."

consul kv put rds/endpoint "$RDS_HOST"

echo "Consul KV configured"

# =============================================================================
# 7. NOMAD: Bootstrap ACL
# =============================================================================
echo ""
echo "[7/8] Bootstrapping Nomad ACL..."

# Check if already bootstrapped
if nomad acl token self &>/dev/null; then
  echo "Nomad ACL already bootstrapped"
  NOMAD_TOKEN=$(nomad acl token self -t '{{.SecretID}}' 2>/dev/null || echo "")
else
  BOOTSTRAP_OUTPUT=$(nomad acl bootstrap -json 2>/dev/null || echo "")
  if [ -n "$BOOTSTRAP_OUTPUT" ]; then
    NOMAD_TOKEN=$(echo "$BOOTSTRAP_OUTPUT" | jq -r '.SecretID')
    echo "Nomad ACL bootstrapped"
    echo "Token: $NOMAD_TOKEN"
  else
    echo "Nomad ACL bootstrap failed or already done"
    NOMAD_TOKEN=""
  fi
fi

# Store Nomad token in Vault
if [ -n "$NOMAD_TOKEN" ]; then
  vault kv put secret/nomad/bootstrap token="$NOMAD_TOKEN"

  # Update Drone runner secret with actual Nomad token
  vault kv patch secret/drone/runner nomad_token="$NOMAD_TOKEN"

  echo "Nomad token stored in Vault"
fi

# =============================================================================
# 8. CREATE DATABASES
# =============================================================================
echo ""
echo "[8/8] Creating application databases..."

mysql -h "${RDS_HOST}" -P "${RDS_PORT}" -u "${RDS_ADMIN_USER}" -p"${RDS_ADMIN_PASS}" <<EOF 2>/dev/null || echo "Databases may already exist"
CREATE DATABASE IF NOT EXISTS wordpress;
CREATE DATABASE IF NOT EXISTS laravel;
EOF

echo "Databases created"

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "=============================================="
echo "Bootstrap complete!"
echo "=============================================="
echo ""
echo "Configured:"
echo "  - Vault KV secrets (wordpress, laravel, drone)"
echo "  - Vault database engine (wordpress, laravel roles)"
echo "  - Vault policies (wordpress, laravel, drone)"
echo "  - Vault JWT auth (nomad-workloads role)"
echo "  - Consul KV (rds/endpoint)"
echo "  - Nomad ACL (token stored in Vault)"
echo "  - MySQL databases (wordpress, laravel)"
echo ""
echo "Next steps:"
echo "  1. Deploy Nomad jobs: nomad job run jobs/system/*.nomad.hcl"
echo "  2. Verify services: consul catalog services"
echo "  3. Test Vault access: vault kv get secret/wordpress/keys"
echo ""
