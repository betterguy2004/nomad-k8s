# Code Standards

Coding conventions and patterns used throughout the Nomad infrastructure project.

## Terraform & Terragrunt

### File Organization

**Directory Structure**
```
infra/
├── environments/dev/           # Environment-specific Terragrunt configs
│   ├── terragrunt.hcl         # Root Terragrunt config (remote state, provider)
│   ├── base-infra/
│   │   ├── terragrunt.hcl     # Base infra module config + variables
│   │   └── *.tf               # (references ../../../stacks/base-infra/)
│   ├── cluster/
│   ├── data/
│   └── cdn/
├── stacks/                     # Terraform modules (reusable)
│   ├── base-infra/
│   │   ├── main.tf            # Primary resources
│   │   ├── vpc.tf             # VPC + subnets + routing
│   │   ├── security-groups.tf
│   │   ├── kms.tf
│   │   ├── route53.tf
│   │   ├── variables.tf       # Input variables
│   │   └── outputs.tf         # Module outputs
│   ├── cluster/
│   ├── data/
│   └── cdn/
├── shared/
│   ├── config/                # HCL config files (Nomad, Consul, Vault)
│   │   ├── nomad.hcl
│   │   ├── consul.hcl
│   │   ├── vault.hcl
│   │   └── consul-template.hcl
│   └── scripts/               # Bash utilities
└── packer/                    # Packer AMI builds
    ├── nomad-cluster.pkr.hcl
    ├── variables.pkr.hcl
    └── dev.pkrvars.hcl
```

**Rationale**: Terragrunt manages environment-specific state; Terraform modules are reusable and testable.

### Naming Conventions

**Resources**
- Use `snake_case` for resource names
- Prefix with logical category: `aws_vpc.main`, `aws_subnet.private`, `aws_instance.nomad_cluster`
- Single-instance resources use `.main`, multi-instance use `.{category}` with `count`

```hcl
# Single
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
}

# Multiple via count
resource "aws_subnet" "private" {
  count  = length(var.private_subnet_cidrs)
  # ...
}

# NOT: aws_subnet_private_1, aws_subnet_private_2 (brittle)
```

**Variables**
- Use `snake_case`
- Group related vars together: `vpc_cidr`, `vpc_enable_dns`, etc.
- Use `var.` prefix in resource references

```hcl
variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"
}
```

**Locals**
- Use `snake_case`
- Aggregate computed values at top of module

```hcl
locals {
  name_prefix = "${var.environment}-${var.app_name}"
  common_tags = {
    Environment = var.environment
    Project     = var.app_name
  }
}
```

**Outputs**
- Use `snake_case`
- Export values needed by downstream modules
- Always include `description`

```hcl
output "vpc_id" {
  description = "VPC ID for security group rules"
  value       = aws_vpc.main.id
}
```

### Terraform Best Practices

**1. Remote State**

Terragrunt manages S3 state backend automatically:

```hcl
# infra/environments/dev/terragrunt.hcl
remote_state {
  backend = "s3"
  config = {
    bucket  = "nomad-infra-tfstate-dev"
    key     = "${path_relative_to_include()}/terraform.tfstate"
    region  = "us-west-1"
    encrypt = true
  }
}
```

**Never commit `.tfstate` or `.tfvars` files to git.**

**2. Provider Configuration**

Centralized in Terragrunt via `generate` block:

```hcl
# infra/environments/dev/terragrunt.hcl
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project
      ManagedBy   = "terragrunt"
    }
  }
}
EOF
}
```

**Benefit**: Avoid repeating provider config across modules; auto-tag all resources.

**3. Count vs For Each**

Use `for_each` for maps, `count` for lists:

```hcl
# For lists (count)
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
}

# For maps (for_each)
resource "aws_security_group_rule" "cluster" {
  for_each = {
    nomad_raft = { from = 8300, to = 8302 }
    consul_rpc = { from = 8500, to = 8500 }
  }
  
  from_port = each.value.from
  to_port   = each.value.to
}
```

**Benefit**: Easier to add/remove items without index shifting.

**4. Conditional Logic**

Use ternary operators for simple conditions:

```hcl
key_name = var.ssh_key_name != "" ? var.ssh_key_name : null

enabled = var.environment == "prod" ? true : false
```

Avoid complex conditionals in resources; move to variables instead.

**5. Local Variables for Computation**

```hcl
locals {
  # Flatten list of maps for easier reference
  security_group_rules = flatten([
    for from_port, to_port in var.internal_ports : {
      from_port = from_port
      to_port   = to_port
      protocol  = "tcp"
    }
  ])
}

resource "aws_security_group_rule" "internal" {
  for_each = {
    for idx, rule in local.security_group_rules : idx => rule
  }
  
  from_port = each.value.from_port
  to_port   = each.value.to_port
}
```

**6. Data Sources for Reusability**

Fetch existing resources instead of hardcoding:

```hcl
# BAD: hardcoded
security_groups = ["sg-12345"]

# GOOD: dynamic lookup
data "aws_security_group" "nomad_cluster" {
  filter {
    name   = "tag:Name"
    values = ["nomad-cluster-sg"]
  }
}

security_groups = [data.aws_security_group.nomad_cluster.id]
```

**7. Lifecycle Rules**

```hcl
# Ignore AMI changes (instances keep old AMI, manual updates)
lifecycle {
  ignore_changes = [ami]
}

# Prevent accidental deletion
lifecycle {
  prevent_destroy = true
}

# Replace instead of update
lifecycle {
  create_before_destroy = true
}
```

### Terragrunt Patterns

**1. Dependency Management**

```hcl
# infra/environments/dev/cluster/terragrunt.hcl
terraform {
  source = "../../../stacks/cluster"
}

dependencies {
  paths = ["../base-infra", "../data"]
}

dependency "base_infra" {
  config_path = "../base-infra"
}

inputs = {
  vpc_id = dependency.base_infra.outputs.vpc_id
}
```

**2. Input Inheritance**

```hcl
# infra/environments/dev/terragrunt.hcl (root)
inputs = {
  environment = "dev"
  project     = "nomad-k8s"
  aws_region  = "us-west-1"
}

# Inherited by all child modules unless overridden
```

**3. Multiple Stacks with Variables**

```bash
# Run plan for base-infra only
cd infra/environments/dev/base-infra
terragrunt plan

# Run all stacks with dependencies
cd infra/environments/dev
terragrunt run-all plan
```

---

## HCL Configuration Files

### Nomad Job Definitions

**Location**: `jobs/*.nomad.hcl`

**Naming Convention**
```
{service-name}.nomad.hcl
system/{system-service}.nomad.hcl
```

Examples: `wordpress.nomad.hcl`, `system/nginx-lb.nomad.hcl`

**Structure**

```hcl
job "wordpress" {
  # Basic metadata
  datacenters = ["dc1"]
  type        = "service"  # or "batch", "system"
  priority    = 50
  
  # Service group (logical grouping of tasks)
  group "wordpress" {
    count = 2  # Replica count for load balancing
    
    # Network configuration
    network {
      port "fpm" { to = 9000 }
    }
    
    # Vault access
    vault {
      policies = ["wordpress"]
    }
    
    # Task (individual container)
    task "wordpress" {
      driver = "docker"
      
      config {
        image = "asdads6495/wordpress:latest"
        ports = ["fpm"]
      }
      
      # Secret injection via Nomad template + Vault
      template {
        data = <<EOF
{{with secret "database/creds/wordpress"}}
DB_USER={{.Data.username}}
DB_PASS={{.Data.password}}
{{end}}
        EOF
        destination = "secrets/env"
        env         = true
      }
      
      # Resource limits
      resources {
        cpu    = 500
        memory = 512
      }
      
      # Service discovery
      service {
        name = "wordpress"
        port = "fpm"
        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
```

**Key Patterns**

1. **Multiple Replicas**: Use `count = N` for horizontal scaling
2. **Vault Integration**: Use `template` block with `{{with secret "..."}}` syntax
3. **Service Registration**: Register with Consul for discovery
4. **Health Checks**: Always include TCP/HTTP checks
5. **Resource Requests**: Be explicit about CPU/memory to aid scheduling

### Consul Configuration

**Location**: `infra/shared/config/consul.hcl`

```hcl
datacenter = "dc1"
data_dir   = "/opt/consul"
node_name  = "${HOSTNAME}"

server = true
ui     = true

bootstrap_expect = 3

# Auto-join via AWS tags
retry_join = [
  "provider=aws tag_key=ConsulAutoJoin tag_value=auto-join region=us-west-1"
]

# Ports
ports {
  http  = 8500
  grpc  = 8502
}

# TLS (optional, not implemented here)
# tls {
#   defaults {
#     ca_file   = "/opt/consul/tls/ca.crt"
#     cert_file = "/opt/consul/tls/consul.crt"
#     key_file  = "/opt/consul/tls/consul.key"
#   }
# }
```

### Vault Configuration

**Location**: `infra/shared/config/vault.hcl`

```hcl
ui = true

# Storage backend (Consul)
storage "consul" {
  address = "127.0.0.1:8500"
  path    = "vault/"
}

# Auto-unseal via AWS KMS
seal "awskms" {
  region     = "us-west-1"
  kms_key_id = "alias/vault-unseal-dev"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = true
}

api_addr     = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"
```

### Nomad Configuration

**Location**: `infra/shared/config/nomad.hcl`

```hcl
datacenter = "dc1"
data_dir   = "/opt/nomad"

# Server (Raft consensus, job scheduling)
server {
  enabled          = true
  bootstrap_expect = 3
  encrypt          = "xxxxx"  # Generated via nomad keygen
}

# Client (task execution)
client {
  enabled = true
}

# Consul integration
consul {
  address = "127.0.0.1:8500"
}

# Vault integration
vault {
  enabled = true
  address = "http://active.vault.service.consul:8200"
}

# Docker driver plugin
plugin "docker" {
  config {
    allow_privileged = true
  }
}
```

---

## Packer

**Location**: `infra/packer/nomad-cluster.pkr.hcl`

**Pattern**: Packer builds an AMI with all services pre-installed and pre-configured.

```hcl
packer {
  required_plugins {
    amazon = {
      version = "~> 1.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-west-1"
}

source "amazon-ebs" "nomad-cluster" {
  ami_name      = "nomad-cluster-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  instance_type = "t3.medium"
  region        = var.aws_region
  
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]  # Canonical
  }
}

build {
  sources = ["source.amazon-ebs.nomad-cluster"]
  
  provisioner "file" {
    source      = "path/to/nomad.hcl"
    destination = "/tmp/nomad.hcl"
  }
  
  provisioner "shell" {
    inline = [
      "sudo mv /tmp/nomad.hcl /opt/nomad/config/nomad.hcl",
      "sudo systemctl start nomad"
    ]
  }
}
```

**Benefits**:
- Faster instance launches (services already installed)
- Consistent baseline across all nodes
- Easier testing of configuration changes
- No user-data script delays

---

## Docker Images

**Location**: `docker/`

**Naming Convention**
```
{service}-{variant}.Dockerfile
```

Examples: `wordpress.Dockerfile`, `laravel.Dockerfile`

**Pattern**

```dockerfile
FROM php:8.1-fpm

# Install dependencies
RUN apt-get update && apt-get install -y \
    git \
    mysql-client \
    && rm -rf /var/lib/apt/lists/*

# Application setup
COPY --chown=www-data:www-data . /var/www/html

WORKDIR /var/www/html

EXPOSE 9000

CMD ["php-fpm"]
```

**Push to Registry**

```bash
# Build locally
docker build -f docker/wordpress.Dockerfile -t asdads6495/wordpress:latest .

# Push to DockerHub
docker push asdads6495/wordpress:latest

# Drone CI/CD builds automatically on commit
```

---

## Bash Scripts

**Location**: `scripts/`, `vault/`, `infra/shared/scripts/`

**Naming Convention**
```
{verb}-{noun}.sh
```

Examples: `init-vault.sh`, `deploy-jobs.sh`

**Template**

```bash
#!/bin/bash
set -euo pipefail

# Strict mode:
# -e: exit on error
# -u: error on undefined variable
# -o pipefail: error if any command in pipe fails

# Logging
log_info() {
  echo "[INFO] $1"
}

log_error() {
  echo "[ERROR] $1" >&2
}

# Main function
main() {
  log_info "Starting deployment..."
  
  if ! command -v nomad &> /dev/null; then
    log_error "nomad CLI not found"
    exit 1
  fi
  
  # ...
}

main "$@"
```

**Key Practices**:
- Always use `set -euo pipefail`
- Create helper functions for common operations
- Log to stdout/stderr appropriately
- Exit with non-zero code on error
- Use `readonly` for constants

```bash
readonly VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
readonly APP_NAME="nomad-k8s"
```

---

## Git Workflow

**Branch Naming**
```
{type}/{description}
feature/nomad-cluster-ha
fix/vault-unseal-race
docs/deployment-guide
```

**Commit Messages**

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

**Examples**:

```
feat(terraform): add multi-az rds support

Add failover RDS instance in secondary AZ for production environment.

Closes #42
```

```
fix(vault): resolve auto-unseal timeout on startup

Increase KMS decrypt timeout from 1s to 5s to accommodate cold KMS keys.

Fixes #38
```

**Ignore Files** (`.gitignore`)

```
# Terraform
*.tfstate*
.terraform/
.terragrunt-cache/
override.tf

# Packer
crash.log

# Vault
.vault-root-token
.vault-unseal-keys

# Environment
.env
.env.local

# IDE
.vscode/
.idea/
*.swp
```

---

## Documentation

**Location**: `docs/`

**Naming Convention**
```
{topic}-{subtopic}.md
```

Examples: `system-architecture.md`, `deployment-guide.md`, `consul-role-overview.md`

**Structure**

```markdown
# Title (H1)

Brief intro (1-2 sentences).

## Section (H2)

### Subsection (H3)

Explanation with code blocks.

## References

- [External Link](https://example.com)

---

See also: [Related Doc](./related-doc.md)
```

**Code Examples**

Always include syntax highlighting:

````markdown
```hcl
resource "aws_instance" "example" {
  ami = "ami-12345"
}
```

```bash
nomad job run example.nomad.hcl
```
````

---

## Summary: Key Principles

| Principle | Example |
|-----------|---------|
| **DRY** | Use Terragrunt for shared configs; Terraform modules for reuse |
| **Single Responsibility** | One stack per infrastructure layer (base, cluster, data, cdn) |
| **Naming** | snake_case for HCL; descriptive names for files; `{type}/{service}` for jobs |
| **IaC First** | Configuration in code, not console; AMI pre-configuration, not user-data |
| **Secrets Management** | All secrets in Vault, never in code; Nomad injects via templates |
| **Observability** | Health checks, logging, CloudWatch integration |
| **Testability** | Modules have clear inputs/outputs; easy to test in isolation |
| **Documentation** | Inline comments for complex logic; separate docs for architecture |

---

See also: [System Architecture](./system-architecture.md), [Deployment Guide](./deployment-guide.md)
