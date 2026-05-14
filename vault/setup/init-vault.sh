#!/bin/bash
set -e

export VAULT_ADDR="http://127.0.0.1:8200"

echo "Checking Vault status..."

if vault status 2>/dev/null | grep -q "Initialized.*true"; then
  echo "Vault already initialized"
  exit 0
fi

echo "Initializing Vault with auto-unseal..."

INIT_OUTPUT=$(vault operator init -key-shares=1 -key-threshold=1 -format=json)

echo "=== SAVE THESE CREDENTIALS SECURELY ==="
echo "$INIT_OUTPUT"
echo "========================================"
echo "WARNING: Credentials shown above will NOT be persisted. Save them NOW!"

sleep 5

ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
vault login "$ROOT_TOKEN"

echo "Vault initialized and logged in successfully"
