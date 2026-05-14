#!/bin/bash
set -e

export VAULT_ADDR="http://127.0.0.1:8200"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Enabling KV v2 secrets engine..."
vault secrets enable -path=secret -version=2 kv 2>/dev/null || true

echo "Storing Drone secrets..."
vault kv put secret/drone \
  dockerhub_username="${DOCKERHUB_USER:-}" \
  dockerhub_password="${DOCKERHUB_PASS:-}" \
  nomad_token="${NOMAD_TOKEN:-}"

echo "Storing WordPress secrets..."
vault kv put secret/wordpress \
  auth_key="$(openssl rand -base64 32)" \
  secure_auth_key="$(openssl rand -base64 32)" \
  logged_in_key="$(openssl rand -base64 32)" \
  nonce_key="$(openssl rand -base64 32)" \
  s3_bucket="${S3_BUCKET:-}" \
  s3_region="us-west-1"

echo "Storing Laravel secrets..."
vault kv put secret/laravel \
  app_key="base64:$(openssl rand -base64 32)" \
  s3_bucket="${S3_BUCKET:-}" \
  s3_region="us-west-1"

echo "Applying Vault policies..."
vault policy write wordpress "${VAULT_DIR}/policies/wordpress.hcl"
vault policy write laravel "${VAULT_DIR}/policies/laravel.hcl"
vault policy write drone "${VAULT_DIR}/policies/drone.hcl"

echo "KV secrets and policies configured successfully"
