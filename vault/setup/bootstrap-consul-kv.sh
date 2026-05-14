#!/bin/bash
set -e

RDS_ENDPOINT="${1}"
RDS_PORT="${2:-3306}"

if [ -z "$RDS_ENDPOINT" ]; then
  echo "Usage: $0 <rds-endpoint> [port]"
  echo "Example: $0 nomad-k8s-dev-mysql.xxxxx.us-west-1.rds.amazonaws.com 3306"
  exit 1
fi

echo "Setting Consul KV for RDS endpoint..."
consul kv put rds/endpoint "${RDS_ENDPOINT}:${RDS_PORT}"

echo "Verifying..."
consul kv get rds/endpoint

echo "Consul KV bootstrap complete"
