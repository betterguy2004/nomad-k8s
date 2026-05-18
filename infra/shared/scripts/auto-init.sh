#!/usr/bin/env bash
# Auto-init script for cluster bootstrap after restart/recreate
# Idempotent: safe to run multiple times, detects existing state
set -e

LOG_TAG="auto-init"
LOG_FILE="/var/log/auto-init.log"
LOCK_KEY="service/auto-init/leader"
MAX_WAIT_CONSUL=120
MAX_WAIT_VAULT=60

log() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') [$LOG_TAG] $1"
    echo "$msg" | tee -a "$LOG_FILE" >&2
    logger -t "$LOG_TAG" "$1"
}

get_ip() {
    curl -s http://169.254.169.254/latest/meta-data/local-ipv4
}

setup_env() {
    local ip
    ip=$(get_ip)
    export CONSUL_HTTP_ADDR="http://${ip}:8500"
    export VAULT_ADDR="http://${ip}:8200"
    export NOMAD_ADDR="http://${ip}:4646"
}

wait_for_consul() {
    log "Waiting for Consul cluster..."
    local waited=0

    while [[ $waited -lt $MAX_WAIT_CONSUL ]]; do
        if consul members &>/dev/null; then
            local alive
            alive=$(consul members 2>/dev/null | grep -c "alive" || echo "0")
            if [[ "$alive" -ge 1 ]]; then
                log "Consul cluster ready with $alive nodes"
                return 0
            fi
        fi
        sleep 5
        waited=$((waited + 5))
    done

    log "ERROR: Consul not ready after ${MAX_WAIT_CONSUL}s"
    return 1
}

wait_for_vault() {
    log "Waiting for Vault..."
    local waited=0

    while [[ $waited -lt $MAX_WAIT_VAULT ]]; do
        if vault status &>/dev/null; then
            log "Vault is responding"
            return 0
        fi
        sleep 3
        waited=$((waited + 3))
    done

    log "ERROR: Vault not ready after ${MAX_WAIT_VAULT}s"
    return 1
}

acquire_leader_lock() {
    log "Attempting to acquire leader lock..."
    local session_id

    # Create session (15m TTL to cover full init time)
    session_id=$(consul session create -name="auto-init-leader" -ttl="15m" -format=json 2>/dev/null | jq -r '.ID' || echo "")
    if [[ -z "$session_id" ]]; then
        log "Failed to create Consul session"
        return 1
    fi

    # Try to acquire lock
    if consul kv put -acquire -session="$session_id" "$LOCK_KEY" "$(hostname)" &>/dev/null; then
        log "Acquired leader lock (session: $session_id)"
        echo "$session_id"
        return 0
    else
        log "Another node is leader, skipping initialization"
        consul session destroy "$session_id" &>/dev/null || true
        return 1
    fi
}

release_leader_lock() {
    local session_id="$1"
    if [[ -n "$session_id" ]]; then
        consul kv delete "$LOCK_KEY" &>/dev/null || true
        consul session destroy "$session_id" &>/dev/null || true
        log "Released leader lock"
    fi
}

check_vault_initialized() {
    local status
    status=$(vault status -format=json 2>/dev/null || echo '{}')
    local initialized
    initialized=$(echo "$status" | jq -r '.initialized // false')

    if [[ "$initialized" == "true" ]]; then
        log "Vault already initialized"
        return 0
    else
        log "Vault NOT initialized"
        return 1
    fi
}

check_vault_sealed() {
    local status
    status=$(vault status -format=json 2>/dev/null || echo '{}')
    local sealed
    sealed=$(echo "$status" | jq -r '.sealed // true')

    [[ "$sealed" == "true" ]]
}

init_vault() {
    log "Initializing Vault..."

    # Initialize with recovery keys for KMS auto-unseal
    local init_output
    init_output=$(vault operator init -recovery-shares=1 -recovery-threshold=1 -format=json 2>&1)

    if [[ $? -ne 0 ]]; then
        log "ERROR: Vault init failed: $init_output"
        return 1
    fi

    local root_token
    root_token=$(echo "$init_output" | jq -r '.root_token')

    # Store root token in Consul KV (encrypted by KMS)
    consul kv put vault/root-token "$root_token"
    log "Vault initialized, root token stored in Consul KV"

    # Export for subsequent operations
    export VAULT_TOKEN="$root_token"
}

get_vault_token() {
    # Try to get root token from Consul KV
    local token
    token=$(consul kv get vault/root-token 2>/dev/null || echo "")

    if [[ -n "$token" ]]; then
        export VAULT_TOKEN="$token"
        log "Retrieved Vault token from Consul KV"
        return 0
    fi

    log "WARNING: No Vault token available"
    return 1
}

check_jwt_auth_configured() {
    vault auth list -format=json 2>/dev/null | jq -e '.["jwt-nomad/"]' &>/dev/null
}

check_secrets_exist() {
    vault kv get secret/wordpress/keys &>/dev/null
}

check_consul_kv_populated() {
    consul kv get rds/endpoint &>/dev/null
}

check_nomad_acl_bootstrapped() {
    # Check if Nomad token exists in Vault
    vault kv get secret/nomad/bootstrap &>/dev/null
}

run_bootstrap_script() {
    log "Running bootstrap-all.sh..."

    # Check multiple possible locations
    local bootstrap_paths=(
        "/opt/scripts/bootstrap-all.sh"
        "/ops/vault/setup/bootstrap-all.sh"
        "/home/ubuntu/bootstrap-all.sh"
    )

    for bootstrap_script in "${bootstrap_paths[@]}"; do
        if [[ -f "$bootstrap_script" ]]; then
            log "Found bootstrap script: $bootstrap_script"
            bash "$bootstrap_script" 2>&1 | tee -a "$LOG_FILE"
            log "Bootstrap script completed"
            return 0
        fi
    done

    log "WARNING: Bootstrap script not found, manual configuration required"
    log "Run: vault/setup/bootstrap-all.sh after setting VAULT_TOKEN"
    return 1
}

health_check() {
    log "Running health checks..."
    local errors=0

    # Consul
    if consul members &>/dev/null; then
        log "  Consul: OK"
    else
        log "  Consul: FAILED"
        ((errors++))
    fi

    # Vault
    if ! check_vault_sealed; then
        log "  Vault: OK (unsealed)"
    else
        log "  Vault: WARNING (sealed)"
        ((errors++))
    fi

    # Nomad
    if nomad server members &>/dev/null; then
        log "  Nomad: OK"
    else
        log "  Nomad: FAILED"
        ((errors++))
    fi

    return $errors
}

main() {
    log "=== Auto-init started ==="
    setup_env

    # Wait for Consul first
    wait_for_consul || exit 1

    # Try to become leader (only one node runs init)
    local session_id
    session_id=$(acquire_leader_lock) || {
        log "Not leader, waiting for leader to complete init..."
        sleep 30
        health_check
        log "=== Auto-init complete (follower) ==="
        exit 0
    }

    # Cleanup on exit
    trap "release_leader_lock '$session_id'" EXIT

    # Wait for Vault
    wait_for_vault || exit 1

    # Check if this is a fresh cluster or existing
    if check_vault_initialized; then
        log "Existing cluster detected (Vault initialized)"

        # Get token for subsequent checks
        if ! get_vault_token; then
            log "WARNING: Cannot retrieve Vault token, some checks will be skipped"
        fi

        # Vault should auto-unseal via KMS
        if check_vault_sealed; then
            log "Waiting for KMS auto-unseal..."
            sleep 10
            if check_vault_sealed; then
                log "ERROR: Vault still sealed after KMS unseal timeout"
            fi
        fi
    else
        log "Fresh cluster detected, running full initialization..."
        init_vault

        # Wait for auto-unseal
        sleep 5
        if check_vault_sealed; then
            log "Waiting for KMS auto-unseal..."
            sleep 10
        fi

        # Run full bootstrap
        run_bootstrap_script || log "WARNING: Bootstrap incomplete"
    fi

    # Verify configuration
    log "Verifying cluster configuration..."

    if [[ -n "${VAULT_TOKEN:-}" ]]; then
        if check_jwt_auth_configured; then
            log "  JWT auth: configured"
        else
            log "  JWT auth: NOT configured"
        fi

        if check_secrets_exist; then
            log "  Secrets: present"
        else
            log "  Secrets: NOT present"
        fi

        if check_nomad_acl_bootstrapped; then
            log "  Nomad ACL: bootstrapped"
        else
            log "  Nomad ACL: NOT bootstrapped"
        fi
    fi

    if check_consul_kv_populated; then
        log "  Consul KV: populated"
    else
        log "  Consul KV: NOT populated"
    fi

    # Final health check
    health_check

    log "=== Auto-init complete (leader) ==="
}

main "$@"
