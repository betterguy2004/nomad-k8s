---
phase: 1
title: "Packer AMI Build"
status: complete
priority: P1
effort: "2h"
dependencies: []
---

# Phase 1: Packer AMI Build

## Overview

Create a custom Amazon Machine Image (AMI) with Nomad, Consul, Vault, Docker, Nginx, and Consul Template pre-installed. This AMI will be used for all 3 cluster nodes.

**Reference:** [HashiCorp Official Nomad Terraform AWS](https://github.com/hashicorp/nomad/tree/main/terraform/aws)

## Requirements

**Functional:**
- AMI based on Ubuntu 22.04 Jammy (following HashiCorp official approach)
- Pre-installed via HashiCorp apt repo:
  - Nomad 2.0.1
  - Consul 1.22.7
  - Vault 2.0.0
  - Consul-template 0.42.0 (CVE fix)
  - Docker CE
  - Nginx
  - **Envoy** (required for Consul Connect mTLS)
- Systemd services configured but not started (user-data will start them)
- Config templates copied to /ops/shared/config

**Non-functional:**
- Build time < 10 minutes
- AMI size < 10GB
- Reproducible builds

## Architecture

```
Packer Build Process (HashiCorp Style):
┌─────────────────────────────────────────────────┐
│ Source AMI: ubuntu/images/hvm-ssd/              │
│             ubuntu-jammy-22.04-amd64-server-*   │
│ Owner: 099720109477 (Canonical)                 │
├─────────────────────────────────────────────────┤
│ Provisioners:                                   │
│ ├─ shell: mkdir /ops && chmod 777               │
│ ├─ file: copy shared/ → /ops/shared             │
│ └─ shell: /ops/shared/scripts/setup.sh          │
├─────────────────────────────────────────────────┤
│ Output: hashistack-{timestamp}                  │
└─────────────────────────────────────────────────┘
```

## Related Code Files

**Create:**
- `infra/packer/nomad-cluster.pkr.hcl`
- `infra/packer/variables.pkr.hcl`
- `infra/packer/dev.pkrvars.hcl`
- `infra/shared/scripts/setup.sh`
- `infra/shared/scripts/server.sh`
- `infra/shared/config/consul.hcl`
- `infra/shared/config/vault.hcl`
- `infra/shared/config/nomad.hcl`
- `infra/shared/config/consul-template.hcl`

## Implementation Steps

1. **Create directory structure**
   ```bash
   mkdir -p infra/packer
   mkdir -p infra/shared/scripts
   mkdir -p infra/shared/config
   ```

2. **Create variables.pkr.hcl**
   ```hcl
   variable "aws_region" {
     type    = string
     default = "us-east-1"
   }
   
   variable "instance_type" {
     type    = string
     default = "t2.medium"
   }
   
   variable "ami_name_prefix" {
     type    = string
     default = "hashistack"
   }
   ```

3. **Create nomad-cluster.pkr.hcl** (based on HashiCorp official)
   ```hcl
   packer {
     required_plugins {
       amazon = {
         source  = "github.com/hashicorp/amazon"
         version = "~> 1"
       }
     }
   }
   
   source "amazon-ebs" "ubuntu" {
     region        = var.aws_region
     instance_type = var.instance_type
     ssh_username  = "ubuntu"
     ami_name      = "${var.ami_name_prefix}-{{timestamp}}"
     
     source_ami_filter {
       filters = {
         virtualization-type = "hvm"
         architecture        = "x86_64"
         name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
         root-device-type    = "ebs"
       }
       owners      = ["099720109477"]  # Canonical
       most_recent = true
     }
     
     tags = {
       Name    = "${var.ami_name_prefix}-{{timestamp}}"
       Project = "nomad-k8s"
     }
   }
   
   build {
     sources = ["source.amazon-ebs.ubuntu"]
     
     provisioner "shell" {
       inline = [
         "sudo mkdir -p /ops",
         "sudo chmod 777 /ops"
       ]
     }
     
     provisioner "file" {
       source      = "../shared"
       destination = "/ops"
     }
     
     provisioner "shell" {
       script = "../shared/scripts/setup.sh"
     }
     
     post-processor "manifest" {
       output     = "manifest.json"
       strip_path = true
     }
   }
   ```

4. **Create setup.sh** (based on HashiCorp official)
   ```bash
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
   ENVOYVERSION=1.29.2  # Compatible with Consul 1.22.x
   
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
   sudo apt-get install -yq nginx
   
   # Install Envoy (required for Consul Connect)
   curl -sL https://func-e.io/install.sh | sudo bash -s -- -b /usr/local/bin
   func-e use ${ENVOYVERSION}
   sudo cp ~/.func-e/versions/${ENVOYVERSION}/bin/envoy /usr/local/bin/
   
   # Install CNI plugins (required for Consul Connect bridge mode)
   CNI_VERSION=1.4.0
   curl -sL https://github.com/containernetworking/plugins/releases/download/v${CNI_VERSION}/cni-plugins-linux-amd64-v${CNI_VERSION}.tgz | \
     sudo tar -xz -C /opt/cni/bin
   
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
   ```

5. **Create config templates**

   **consul.hcl:**
   ```hcl
   datacenter = "dc1"
   data_dir   = "/opt/consul"
   
   server           = true
   bootstrap_expect = SERVER_COUNT
   
   bind_addr   = "IP_ADDRESS"
   client_addr = "0.0.0.0"
   
   retry_join = ["RETRY_JOIN"]
   
   connect {
     enabled = true
   }
   
   ui_config {
     enabled = true
   }
   ```

   **vault.hcl:**
   ```hcl
   storage "consul" {
     address = "127.0.0.1:8500"
     path    = "vault/"
   }
   
   listener "tcp" {
     address     = "0.0.0.0:8200"
     tls_disable = 1
   }
   
   seal "awskms" {
     region     = "REGION"
     kms_key_id = "KMS_KEY_ID"
   }
   
   api_addr     = "http://IP_ADDRESS:8200"
   cluster_addr = "https://IP_ADDRESS:8201"
   ui           = true
   ```

   **nomad.hcl:**
   ```hcl
   datacenter = "dc1"
   data_dir   = "/opt/nomad"
   
   server {
     enabled          = true
     bootstrap_expect = SERVER_COUNT
   }
   
   client {
     enabled = true
   }
   
   consul {
     address = "127.0.0.1:8500"
   }
   
   vault {
     enabled = true
     address = "http://active.vault.service.consul:8200"
   }
   ```

6. **Create server.sh** (user-data bootstrap script)
   ```bash
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
   sudo systemctl start consul
   sleep 10
   sudo systemctl start vault
   sleep 5
   sudo systemctl start nomad
   
   # Set env vars
   echo "export CONSUL_HTTP_ADDR=$IP_ADDRESS:8500" >> ~/.bashrc
   echo "export VAULT_ADDR=http://$IP_ADDRESS:8200" >> ~/.bashrc
   echo "export NOMAD_ADDR=http://$IP_ADDRESS:4646" >> ~/.bashrc
   ```

7. **Create dev.pkrvars.hcl**
   ```hcl
   aws_region      = "us-west-1"  # Changed from us-east-1 for quota
   instance_type   = "t2.medium"
   ami_name_prefix = "nomad-cluster-dev"
   ```
   
   > **Note:** AMI sẽ được build ở us-west-1. Source AMI filter tự động tìm Ubuntu 22.04 AMI phù hợp cho region.

8. **Validate and build**
   ```bash
   cd infra/packer
   packer init .
   packer validate -var-file=dev.pkrvars.hcl .
   packer build -var-file=dev.pkrvars.hcl .
   
   # Note AMI ID from manifest.json
   cat manifest.json | jq -r '.builds[-1].artifact_id' | cut -d: -f2
   ```

## Success Criteria

- [ ] `packer validate` passes without errors
- [ ] `packer build` completes successfully (< 10 min)
- [ ] AMI appears in AWS console with correct tags
- [ ] AMI can launch EC2 instance
- [ ] All services exist: `systemctl status consul vault nomad docker nginx`
- [ ] Services are enabled but inactive (will start via user-data)
- [ ] HashiCorp versions: Nomad 2.0.1, Consul 1.22.7, Vault 2.0.0, Consul-template 0.42.0
- [ ] Envoy installed: `envoy --version` returns 1.29.x
- [ ] CNI plugins installed: `/opt/cni/bin/bridge` exists

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| HashiCorp repo unavailable | Pin package versions explicitly |
| AMI build timeout | Use t2.medium (not t2.micro) |
| Region-specific AMI IDs | Use source_ami_filter with Canonical owner |
| Docker GPG key rotation | Check Docker docs for latest key URL |

## References

- [HashiCorp Nomad Terraform AWS](https://github.com/hashicorp/nomad/tree/main/terraform/aws)
- [HashiCorp setup.sh](https://github.com/hashicorp/nomad/blob/main/terraform/shared/scripts/setup.sh)
- [HashiCorp packer.json](https://github.com/hashicorp/nomad/blob/main/terraform/aws/packer.json)
