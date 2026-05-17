#!/bin/bash
set -e

# WordPress Vault Migration Script
# Migrates hardcoded secrets to HashiCorp Vault using Nomad Workload Identity

VAULT_ADDR="${VAULT_ADDR:?VAULT_ADDR required}"
VAULT_TOKEN="${VAULT_TOKEN:?VAULT_TOKEN required}"
SSH_KEY="${SSH_KEY:-/tmp/nomad-key.pem}"
# Set NOMAD_NODES as space-separated IPs, e.g.: "10.0.1.1 10.0.1.2 10.0.1.3"
IFS=' ' read -ra NODES <<< "${NOMAD_NODES:?NOMAD_NODES required (space-separated IPs)}"

export VAULT_ADDR VAULT_TOKEN

echo "=== WordPress Vault Migration ==="
echo "Vault: $VAULT_ADDR"
echo ""

# Phase 1: Deploy Nomad Config
phase1_deploy_config() {
    echo "=== Phase 1: Deploy Nomad Config ==="

    for NODE in "${NODES[@]}"; do
        echo "Deploying to $NODE..."
        scp -i "$SSH_KEY" -o StrictHostKeyChecking=no infra/shared/config/nomad.hcl ubuntu@$NODE:/tmp/
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@$NODE "sudo cp /etc/nomad.d/nomad.hcl /etc/nomad.d/nomad.hcl.bak && sudo cp /tmp/nomad.hcl /etc/nomad.d/nomad.hcl"
    done
    echo "Config deployed to all nodes"
}

# Phase 1: Rolling restart
phase1_restart() {
    echo "=== Phase 1: Rolling Restart ==="

    for NODE in "${NODES[@]}"; do
        echo "Restarting Nomad on $NODE..."
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@$NODE "sudo systemctl restart nomad"
        echo "Waiting 30s for cluster to stabilize..."
        sleep 30
    done
    echo "All nodes restarted"
}

# Phase 1: Bootstrap ACL
phase1_bootstrap() {
    echo "=== Phase 1: Bootstrap ACL ==="
    echo "Run this on the first node:"
    echo "  ssh -i $SSH_KEY ubuntu@${NODES[0]} 'nomad acl bootstrap'"
    echo ""
    echo "SAVE THE OUTPUT - this is your management token!"
    echo "Set NOMAD_TOKEN env var with the bootstrap token"
}

# Phase 2: Configure Vault JWT Auth
phase2_vault_auth() {
    echo "=== Phase 2: Configure Vault JWT Auth ==="

    echo "Enabling JWT auth method..."
    vault auth enable -path=jwt-nomad jwt 2>/dev/null || echo "JWT auth already enabled"

    echo "Configuring JWT auth..."
    vault write auth/jwt-nomad/config \
        jwks_url="http://nomad.service.consul:4646/.well-known/jwks.json" \
        jwt_supported_algs="RS256,EdDSA" \
        default_role="nomad-workloads"

    echo "Creating wordpress-secrets policy..."
    vault policy write wordpress-secrets - <<EOF
path "secret/data/wordpress/*" {
  capabilities = ["read"]
}
EOF

    echo "Creating nomad-workloads role..."
    vault write auth/jwt-nomad/role/nomad-workloads \
        role_type="jwt" \
        bound_audiences="vault.io" \
        user_claim="nomad_job_id" \
        claim_mappings='{"nomad_namespace":"nomad_namespace","nomad_job_id":"nomad_job_id","nomad_task":"nomad_task"}' \
        token_policies="wordpress-secrets" \
        token_period="30m" \
        token_type="service"

    echo "Phase 2 complete"
}

# Phase 3: Store Secrets in Vault
phase3_store_secrets() {
    echo "=== Phase 3: Store Secrets in Vault ==="

    echo "Enabling KV v2 secrets engine..."
    vault secrets enable -path=secret -version=2 kv 2>/dev/null || echo "KV already enabled"

    echo "Storing WordPress keys..."
    echo "Generate keys at: https://api.wordpress.org/secret-key/1.1/salt/"
    vault kv put secret/wordpress/keys \
        auth_key="${WP_AUTH_KEY:?WP_AUTH_KEY required}" \
        secure_auth_key="${WP_SECURE_AUTH_KEY:?WP_SECURE_AUTH_KEY required}" \
        logged_in_key="${WP_LOGGED_IN_KEY:?WP_LOGGED_IN_KEY required}" \
        nonce_key="${WP_NONCE_KEY:?WP_NONCE_KEY required}" \
        auth_salt="${WP_AUTH_SALT:?WP_AUTH_SALT required}" \
        secure_auth_salt="${WP_SECURE_AUTH_SALT:?WP_SECURE_AUTH_SALT required}" \
        logged_in_salt="${WP_LOGGED_IN_SALT:?WP_LOGGED_IN_SALT required}" \
        nonce_salt="${WP_NONCE_SALT:?WP_NONCE_SALT required}"

    echo "Storing WordPress DB credentials..."
    vault kv put secret/wordpress/db \
        host="${WP_DB_HOST:?WP_DB_HOST required}" \
        user="${WP_DB_USER:?WP_DB_USER required}" \
        password="${WP_DB_PASSWORD:?WP_DB_PASSWORD required}" \
        name="${WP_DB_NAME:?WP_DB_NAME required}"

    echo "Verifying secrets..."
    vault kv get secret/wordpress/keys
    vault kv get secret/wordpress/db

    echo "Phase 3 complete"
}

# Phase 4: Deploy WordPress Job
phase4_deploy_job() {
    echo "=== Phase 4: Deploy WordPress Job ==="

    if [ -z "$NOMAD_TOKEN" ]; then
        echo "ERROR: NOMAD_TOKEN not set. Run phase1_bootstrap first."
        exit 1
    fi

    echo "Planning job..."
    nomad job plan jobs/wordpress.nomad.hcl

    echo ""
    read -p "Deploy job? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        nomad job run jobs/wordpress.nomad.hcl
        echo "Monitoring deployment..."
        nomad job status wordpress
    fi
}

# Verification
verify() {
    echo "=== Verification ==="

    echo "Checking JWKS endpoint..."
    curl -s http://${NODES[0]}:4646/.well-known/jwks.json | head -c 100
    echo ""

    echo "Checking Vault auth..."
    vault read auth/jwt-nomad/config

    echo "Checking Vault role..."
    vault read auth/jwt-nomad/role/nomad-workloads

    echo "Checking WordPress job..."
    nomad job status wordpress 2>/dev/null || echo "Job not deployed yet"
}

# Main
case "${1:-help}" in
    phase1-config)  phase1_deploy_config ;;
    phase1-restart) phase1_restart ;;
    phase1-bootstrap) phase1_bootstrap ;;
    phase2)         phase2_vault_auth ;;
    phase3)         phase3_store_secrets ;;
    phase4)         phase4_deploy_job ;;
    verify)         verify ;;
    all)
        phase1_deploy_config
        phase1_restart
        phase1_bootstrap
        echo "--- Run 'nomad acl bootstrap' manually, then continue ---"
        ;;
    vault-only)
        phase2_vault_auth
        phase3_store_secrets
        ;;
    *)
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  phase1-config    Deploy Nomad config to all nodes"
        echo "  phase1-restart   Rolling restart of Nomad services"
        echo "  phase1-bootstrap Print ACL bootstrap instructions"
        echo "  phase2           Configure Vault JWT auth"
        echo "  phase3           Store secrets in Vault"
        echo "  phase4           Deploy WordPress job"
        echo "  verify           Verify the setup"
        echo "  all              Run phases 1 (config + restart)"
        echo "  vault-only       Run phases 2 + 3 (Vault setup)"
        echo ""
        echo "Typical workflow:"
        echo "  1. ./vault-migration.sh phase1-config"
        echo "  2. ./vault-migration.sh phase1-restart"
        echo "  3. ssh to node and run: nomad acl bootstrap"
        echo "  4. export NOMAD_TOKEN=<bootstrap-token>"
        echo "  5. ./vault-migration.sh vault-only"
        echo "  6. ./vault-migration.sh phase4"
        echo "  7. ./vault-migration.sh verify"
        ;;
esac
