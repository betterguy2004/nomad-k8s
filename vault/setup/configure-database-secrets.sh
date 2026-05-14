#!/bin/bash
set -e

export VAULT_ADDR="http://127.0.0.1:8200"

RDS_HOST="${1:-mysql.example.com}"
RDS_PORT="${2:-3306}"
RDS_ADMIN_USER="${3:-admin}"
RDS_ADMIN_PASS="${4}"

if [ -z "$RDS_ADMIN_PASS" ]; then
  echo "Usage: $0 <host> <port> <user> <password>"
  exit 1
fi

echo "Enabling database secrets engine..."
vault secrets enable -path=database database 2>/dev/null || true

echo "Configuring MySQL connection..."
vault write database/config/mysql \
  plugin_name=mysql-database-plugin \
  connection_url="{{username}}:{{password}}@tcp(${RDS_HOST}:${RDS_PORT})/" \
  allowed_roles="wordpress,laravel" \
  username="${RDS_ADMIN_USER}" \
  password="${RDS_ADMIN_PASS}"

echo "Creating WordPress role..."
vault write database/roles/wordpress \
  db_name=mysql \
  creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT ALL ON wordpress.* TO '{{name}}'@'%';" \
  default_ttl="1h" \
  max_ttl="24h"

echo "Creating Laravel role..."
vault write database/roles/laravel \
  db_name=mysql \
  creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT ALL ON laravel.* TO '{{name}}'@'%';" \
  default_ttl="1h" \
  max_ttl="24h"

echo "Creating application databases..."
mysql -h "${RDS_HOST}" -P "${RDS_PORT}" -u "${RDS_ADMIN_USER}" -p"${RDS_ADMIN_PASS}" <<EOF
CREATE DATABASE IF NOT EXISTS wordpress;
CREATE DATABASE IF NOT EXISTS laravel;
EOF

echo "Database secrets engine configured successfully"
