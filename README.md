# AWS Nomad Infrastructure

Production-grade AWS infrastructure using HashiCorp stack (Nomad, Consul, Vault) with Terraform/Terragrunt IaC. Orchestrates containerized workloads (WordPress, Laravel, Nginx, Drone CI) across a managed cluster with secrets management, service discovery, and mTLS encryption.

## Quick Links

- **Architecture**: See [System Architecture](./docs/system-architecture.md)
- **Deployment**: See [Deployment Guide](./docs/deployment-guide.md)
- **Consul Integration**: See [Consul Role Overview](./docs/consul-role-overview.md)
- **Secrets Management**: See [Secrets Management Flow](./docs/secrets-management-flow.md)

## Directory Structure

```
nomad-k8s/
├── infra/                    # Infrastructure as Code
│   ├── environments/dev/     # Terragrunt env configs (VPC, cluster, data, CDN)
│   ├── stacks/              # Terraform modules
│   │   ├── base-infra/      # VPC, security groups, KMS, Route53
│   │   ├── cluster/         # EC2 instances, IAM, Nomad/Consul/Vault setup
│   │   ├── data/            # RDS MySQL, S3 buckets
│   │   └── cdn/             # CloudFront + ACM
│   ├── packer/              # Packer AMI template (HashiStack preinstalled)
│   └── shared/              # Config files for Nomad, Consul, Vault
├── jobs/                    # Nomad job definitions
│   ├── wordpress.nomad.hcl
│   ├── laravel.nomad.hcl
│   ├── system/              # System jobs (nginx-lb, drone-*, etc.)
│   └── vars/                # Job variable files
├── vault/                   # Vault initialization & policy scripts
├── docker/                  # Application Docker images
├── scripts/                 # Utility scripts (deploy, health check, etc.)
└── docs/                    # Documentation
```

## Prerequisites

- **Terraform** >= 1.5 (`terraform --version`)
- **Terragrunt** >= 0.48 (`terragrunt --version`)
- **Packer** >= 1.8 (`packer --version`)
- **AWS CLI** >= 2.0 configured with credentials (`aws sts get-caller-identity`)
- **Nomad CLI** >= 1.6 (for job management)
- **Consul CLI** >= 1.15 (for service discovery)
- **Vault CLI** >= 1.13 (for secrets)

### Setup Check

```bash
terraform --version && terragrunt --version && packer --version
aws sts get-caller-identity
```

## Deployment Order

Run these steps **in sequence**. Each depends on previous outputs.

### 1. Build AMI (Packer)

```bash
cd infra/packer
packer build -var-file=dev.pkrvars.hcl nomad-cluster.pkr.hcl
# Captures AMI ID for next step
```

### 2. Deploy Base Infrastructure

```bash
cd infra/environments/dev/base-infra
terragrunt apply
# Creates: VPC, subnets, security groups, KMS, Route53
```

### 3. Deploy Data Layer (RDS + S3)

```bash
cd infra/environments/dev/data
terragrunt apply
# Creates: RDS MySQL, S3 buckets for media storage
```

### 4. Deploy EC2 Cluster

```bash
cd infra/environments/dev/cluster
terragrunt apply
# Creates: 3 EC2 instances with Nomad/Consul/Vault pre-configured
# Cluster auto-joins via AWS tags
```

### 5. Initialize Vault

```bash
cd vault
./init-vault.sh
# Generates Vault root token, configures database engine, policies
```

### 6. Deploy CDN (CloudFront)

```bash
cd infra/environments/dev/cdn
terragrunt apply
# Creates: CloudFront distribution for media delivery
```

### 7. Run Nomad Jobs

```bash
cd jobs
# Deploy WordPress
nomad job run wordpress.nomad.hcl

# Deploy Laravel
nomad job run laravel.nomad.hcl

# Deploy system jobs (nginx, drone)
nomad job run system/nginx-lb.nomad.hcl
nomad job run system/drone-*.nomad.hcl
```

## Verify Deployment

```bash
# Check cluster status
nomad node status
consul members

# Check running jobs
nomad job status

# Check service discovery
consul catalog services

# Access UIs
# Nomad UI: http://<cluster-ip>:4646
# Consul UI: http://<cluster-ip>:8500
# Vault UI: http://<cluster-ip>:8200
```

## Key Features

| Component | Purpose | Status |
|-----------|---------|--------|
| **VPC** | Network isolation, subnets, routing | ✓ Configured |
| **RDS MySQL** | Database for WordPress/Laravel | ✓ Configured |
| **S3** | Media storage for WordPress/Laravel | ✓ Configured |
| **CloudFront** | CDN for S3 content delivery | ✓ Configured |
| **KMS** | Vault auto-unseal encryption | ✓ Configured |
| **EC2** | 3 nodes (Nomad servers + clients) | ✓ Configured |
| **Nomad** | Workload orchestration | ✓ Configured |
| **Consul** | Service discovery + Connect mesh | ✓ Configured |
| **Vault** | Secrets management | ✓ Configured |
| **Drone CI** | CI/CD pipeline orchestration | ✓ Configured |

## Troubleshooting

### Cluster doesn't join
```bash
# Check Consul logs
nomad alloc logs <alloc-id> | grep consul

# Verify EC2 tags for auto-join
aws ec2 describe-tags --filters "Name=resource-type,Values=instance"
```

### Vault sealed
```bash
# Auto-unseal via KMS (automatic)
vault status  # Check if unsealed
```

### Services not discovered
```bash
consul catalog services
consul health service wordpress
```

See [Deployment Guide](./docs/deployment-guide.md) for detailed troubleshooting.

## Security

- **Network**: Consul Connect mTLS encrypts all inter-service traffic
- **Secrets**: Vault manages all credentials with dynamic database secrets + static KV store
- **Access Control**: Consul Intentions enforce service-to-service ACLs
- **Infrastructure**: IAM roles restrict EC2 access; KMS encrypts Vault seal key
- **Auto-Unseal**: Vault automatically unseals via KMS (no manual intervention)

See [Secrets Management Flow](./docs/secrets-management-flow.md) for details.

## Environment Variables

Create `.env` in project root (not committed):

```bash
# AWS
AWS_REGION=us-west-1
AWS_PROFILE=default

# Terraform
TF_VAR_environment=dev
TF_VAR_app_name=nomad-k8s

# Packer
PKR_VAR_aws_region=us-west-1
```

## License

Internal project. See LICENSE if applicable.
