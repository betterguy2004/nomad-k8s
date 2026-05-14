#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive
cd /ops

CONFIGDIR=/ops/shared/config

# Versions (updated May 2026)
NOMADVERSION=2.0.1
CONSULVERSION=1.22.7
VAULTVERSION=2.0.0
CONSULTEMPLATEVERSION=0.42.0
ENVOYVERSION=1.29.2

echo "Installing HashiCorp products..."

# Add HashiCorp apt repo
sudo apt-get update && sudo apt-get install -yq gpg
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

# Install HashiCorp products
sudo apt-get update
sudo apt-get install -yq \
  consul="${CONSULVERSION}*" \
  vault="${VAULTVERSION}*" \
  nomad="${NOMADVERSION}*" \
  consul-template="${CONSULTEMPLATEVERSION}*"

# Install dependencies
sudo apt-get install -yq unzip tree jq curl

echo "Installing Docker CE..."

# Install Docker CE
sudo apt-get install -yq ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -yq docker-ce docker-ce-cli containerd.io

# Install Nginx
echo "Installing Nginx..."
sudo apt-get install -yq nginx

# Install Envoy (required for Consul Connect)
echo "Installing Envoy ${ENVOYVERSION}..."
curl -sL "https://archive.tetratelabs.io/envoy/download/v${ENVOYVERSION}/envoy-v${ENVOYVERSION}-linux-amd64.tar.xz" -o /tmp/envoy.tar.xz
sudo tar -xJf /tmp/envoy.tar.xz -C /usr/local/bin --strip-components=2 envoy-v${ENVOYVERSION}-linux-amd64/bin/envoy
sudo chmod +x /usr/local/bin/envoy
rm /tmp/envoy.tar.xz

# Install CNI plugins (required for Consul Connect bridge mode)
echo "Installing CNI plugins..."
CNI_VERSION=1.4.0
sudo mkdir -p /opt/cni/bin
curl -sL https://github.com/containernetworking/plugins/releases/download/v${CNI_VERSION}/cni-plugins-linux-amd64-v${CNI_VERSION}.tgz | \
  sudo tar -xz -C /opt/cni/bin

# Create config directories
sudo mkdir -p /etc/consul.d
sudo mkdir -p /etc/vault.d
sudo mkdir -p /etc/nomad.d
sudo mkdir -p /opt/consul
sudo mkdir -p /opt/vault
sudo mkdir -p /opt/nomad

# Enable services (but don't start - user-data will start them)
sudo systemctl enable consul
sudo systemctl enable vault
sudo systemctl enable nomad
sudo systemctl enable docker
sudo systemctl enable nginx

# Cleanup
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

echo "Setup complete!"
