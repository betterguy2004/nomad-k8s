#!/usr/bin/env bash
set -e

CONFIGDIR=/ops/shared/config
CONSULCONFIGDIR=/etc/consul.d
VAULTCONFIGDIR=/etc/vault.d
NOMADCONFIGDIR=/etc/nomad.d

# Wait for network
sleep 15

CLOUD=$1
SERVER_COUNT=$2
RETRY_JOIN=$3
REGION=$4
KMS_KEY_ID=$5

# Get IP from metadata service
IP_ADDRESS=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

echo "Configuring services for IP: $IP_ADDRESS"

# Configure Consul
sed -e "s/IP_ADDRESS/$IP_ADDRESS/g" \
    -e "s/SERVER_COUNT/$SERVER_COUNT/g" \
    -e "s/RETRY_JOIN/$RETRY_JOIN/g" \
    $CONFIGDIR/consul.hcl | sudo tee $CONSULCONFIGDIR/consul.hcl

# Configure Vault
sed -e "s/IP_ADDRESS/$IP_ADDRESS/g" \
    -e "s/REGION/$REGION/g" \
    -e "s/KMS_KEY_ID/$KMS_KEY_ID/g" \
    $CONFIGDIR/vault.hcl | sudo tee $VAULTCONFIGDIR/vault.hcl

# Configure Nomad
sed -e "s/SERVER_COUNT/$SERVER_COUNT/g" \
    $CONFIGDIR/nomad.hcl | sudo tee $NOMADCONFIGDIR/nomad.hcl

# Start services in order
echo "Starting Consul..."
sudo systemctl start consul
sleep 10

echo "Starting Vault..."
sudo systemctl start vault
sleep 5

echo "Starting Nomad..."
sudo systemctl start nomad

# Set env vars
echo "export CONSUL_HTTP_ADDR=$IP_ADDRESS:8500" >> ~/.bashrc
echo "export VAULT_ADDR=http://$IP_ADDRESS:8200" >> ~/.bashrc
echo "export NOMAD_ADDR=http://$IP_ADDRESS:4646" >> ~/.bashrc

echo "Server bootstrap complete!"
