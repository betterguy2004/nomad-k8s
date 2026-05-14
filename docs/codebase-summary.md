# Codebase Summary

High-level overview of the Nomad Kubernetes infrastructure project structure and component responsibilities.

## Project Overview

**nomad-k8s** is a production-ready AWS infrastructure deployment using HashiCorp HashiStack (Terraform/Terragrunt for IaC, Packer for AMI builds, Nomad for orchestration, Consul for service discovery, and Vault for secrets).

**Size**: ~2,900 lines of documentation, ~1,500+ lines of Terraform/HCL, ~500+ lines of job definitions

**Status**: Fully implemented with all core infrastructure and application workloads deployed.

## Directory Map

### Root Level

```
nomad-k8s/
├── README.md                          # Project overview, quick start (209 LOC)
├── .git/                              # Git repository
├── .gitignore                         # Exclude tfstate, .env, IDE files
├── .claude/                           # Claude Code context (not tracked)
└── infra/                             # Infrastructure as Code
    jobs/                              # Nomad job definitions
    vault/                             # Vault initialization
    docker/                            # Application Docker images
    scripts/                           # Deployment utilities
    docs/                              # Documentation (2,927 LOC total)
```

---

## `infra/` Directory (Infrastructure as Code)

### `infra/environments/dev/` (Terragrunt Root)

**Purpose**: Environment-specific Terragrunt configuration and module composition.

**Files**:
- `terragrunt.hcl` (59 LOC) — Root configuration
  - Defines S3 remote state backend
  - Generates provider.tf with AWS + Terraform versions
  - Sets common input variables (environment, project, region)
  - Child modules inherit these settings

**Subdirectories**:
- `base-infra/` — VPC, security groups, KMS, Route53
- `cluster/` — EC2 instances, IAM roles
- `data/` — RDS MySQL, S3 buckets
- `cdn/` — CloudFront distribution

Each subdirectory has:
- `terragrunt.hcl` — Module-specific config + dependency declaration
- (No .tf files; references `source = "../../../stacks/{module}/"`)

**Advantage**: Cleanly separates environment config from reusable modules; enables multiple environments (dev, staging, prod) with different values.

### `infra/stacks/` (Terraform Modules)

**Purpose**: Reusable Terraform modules, platform-agnostic (can be tested independently).

#### `base-infra/` Stack (Network + Security)

**Files**:
- `main.tf` (30 LOC) — Provider setup, local variables
- `vpc.tf` (150+ LOC) — VPC, subnets, internet gateway, route tables
- `security-groups.tf` (200+ LOC) — Security groups for Nomad cluster, RDS, ALB
- `kms.tf` (50+ LOC) — KMS key for Vault auto-unseal
- `route53.tf` (80+ LOC) — DNS zone + records
- `variables.tf` (100+ LOC) — Input variable definitions
- `outputs.tf` (60+ LOC) — VPC ID, subnet IDs, security group IDs

**Key Exports**:
- `vpc_id` — Used by cluster and data stacks
- `private_subnet_ids` — For EC2 instance placement
- `security_group_nomad_id` — For cluster ingress/egress rules
- `kms_key_id` — For Vault auto-unseal configuration

#### `cluster/` Stack (EC2 + Nomad/Consul/Vault)

**Files**:
- `main.tf` (40 LOC) — Locals and provider setup
- `ec2.tf` (80+ LOC) — 3 EC2 instances (t3.medium), user-data template
- `iam.tf` (120+ LOC) — IAM role + policy (EC2, Consul auto-join, KMS)
- `variables.tf` (80+ LOC) — instance_type, ami_id, key_name, etc.
- `outputs.tf` (40+ LOC) — instance_ids, load_balancer_dns

**Key Features**:
- `count = var.server_count` — Creates N identical nodes
- User-data template: `user-data.tftpl` — Injects cluster name, region, KMS key
- EC2 tags for Consul auto-join: `ConsulAutoJoin = auto-join`
- IAM policy allows: EC2 describe, KMS decrypt, S3 objects

#### `data/` Stack (RDS + S3)

**Files**:
- `main.tf` (20 LOC) — Locals and provider
- `rds.tf` (100+ LOC) — RDS MySQL instance (db.t3.micro)
  - Database name: `nomad`
  - Master user: `admin`
  - Multi-AZ: false (dev only)
- `s3.tf` (80+ LOC) — 2 buckets
  - `nomad-media-{hash}-dev` — Application media
  - `nomad-backups-{hash}-dev` — Backup storage
- `variables.tf` (60+ LOC)
- `outputs.tf` (30+ LOC) — RDS endpoint, bucket names

**Key Features**:
- Bucket versioning enabled
- Server-side encryption (KMS)
- Endpoint stored in Consul KV at `rds/endpoint`

#### `cdn/` Stack (CloudFront)

**Files**:
- `main.tf` (20 LOC)
- `acm.tf` (50+ LOC) — SSL certificate (ACM)
- `cloudfront.tf` (100+ LOC) — Distribution with S3 origin
- `variables.tf` (50+ LOC)
- `outputs.tf` (20+ LOC)

**Key Features**:
- Origin: S3 bucket `nomad-media-xxx-dev`
- Cache behaviors: 24h for images, 1h for others
- Custom domain via Route53 CNAME

---

### `infra/packer/` (AMI Builds)

**Purpose**: Create machine images with Nomad, Consul, Vault pre-installed and configured.

**Files**:
- `nomad-cluster.pkr.hcl` (150+ LOC) — Main build definition
  - Source: Ubuntu 22.04 LTS (Canonical AMI)
  - Provisioners:
    - `file` — Copy config files
    - `shell` — Install software, configure systemd
  - Outputs: AMI ID (`ami-0c8f...`)
- `variables.pkr.hcl` (30+ LOC) — Input variable definitions
- `dev.pkrvars.hcl` (20+ LOC) — Dev environment values

**Benefits**:
- Faster EC2 startup (no user-data delays)
- Consistent baseline
- Easier to test configuration changes offline

---

### `infra/shared/` (Shared Configuration)

**Purpose**: Configuration files used by services in EC2 instances.

#### `config/` Subdirectory

**Files**:
- `nomad.hcl` (30 LOC) — Nomad server + client config
  - Bootstrap expect: 3 (Raft consensus)
  - Consul integration enabled
  - Vault integration enabled
  - Docker plugin allowed
- `consul.hcl` (40 LOC) — Consul server config
  - Server mode enabled
  - Auto-join via AWS EC2 tags
  - Retry join: `provider=aws tag_key=ConsulAutoJoin tag_value=auto-join`
- `vault.hcl` (30 LOC) — Vault server config
  - Storage backend: Consul KV
  - Auto-unseal: AWS KMS
  - Listener on 0.0.0.0:8200 (TLS disabled in dev)
- `consul-template.hcl` (20+ LOC) — Template configuration for Nginx

**Deployment**: Copied into AMI by Packer; placed at `/opt/{nomad,consul,vault}/config/`

#### `scripts/` Subdirectory

**Purpose**: Utility scripts referenced during Packer build or Terraform execution.

---

## `jobs/` Directory (Nomad Job Definitions)

**Purpose**: Define workloads to run on the Nomad cluster.

### Application Jobs

**Files**:
- `wordpress.nomad.hcl` (50+ LOC)
  - 2 replicas, 500 CPU / 512 MB RAM each
  - FPM on port 9000
  - Template: Vault DB creds + KV secrets
  - Service: `wordpress.service.consul`
  - Health check: TCP port 9000
  
- `laravel.nomad.hcl` (50+ LOC)
  - 2 replicas
  - Prestart task: Database migrations
  - Main task: FPM on port 9000
  - Template: Vault DB creds
  - Service: `laravel.service.consul`

### System Jobs

**Directory**: `system/`

**Files**:
- `nginx-lb.nomad.hcl` (80+ LOC)
  - 1 replica (single entry point)
  - Ports: 80 (HTTP), 443 (HTTPS)
  - Consul Template: Auto-generates upstream blocks
  - Watches Consul catalog; reloads on changes
  
- `drone-server.nomad.hcl` (50+ LOC)
  - CI/CD orchestration
  - Stores config in Consul KV
  - Vault extension integration
  
- `drone-runner.nomad.hcl` (40+ LOC)
  - Task execution
  - Docker container jobs
  - Pulls credentials from Vault
  
- `drone-vault.nomad.hcl` (30+ LOC)
  - Bridge between Drone and Vault
  - Enables `.drone.yml` secret references

### Variables

**Directory**: `vars/`

**Purpose**: Job variable files (environment-specific overrides).

---

## `vault/` Directory (Secrets Management)

**Purpose**: Initialize Vault, create policies, and set up secret engines.

**Files**:
- `init-vault.sh` (100+ LOC) — Main initialization script
  - Initialize Vault (only if not already)
  - Configure database engine (RDS MySQL)
  - Create roles: `database/roles/{wordpress,laravel}`
  - Create policies: `wordpress`, `laravel`, `drone`, `nomad-server`
  - Create KV v2 secrets: `secret/{wordpress,laravel,drone}`
  - Output: Root token (stored in `.vault-root-token`)

**Vault Paths Created**:
```
database/config/mysql
database/roles/wordpress
database/roles/laravel

secret/data/wordpress
secret/data/laravel
secret/data/drone

sys/policy/wordpress
sys/policy/laravel
sys/policy/drone
sys/policy/nomad-server
```

---

## `docker/` Directory (Container Images)

**Purpose**: Application Docker images, pushed to registry.

**Pattern**: `{service}.Dockerfile`

**Files**:
- `wordpress.Dockerfile` — PHP 8.1-FPM + WordPress plugins
- `laravel.Dockerfile` — PHP 8.1-FPM + Laravel framework
- Build command: `docker build -f docker/{service}.Dockerfile -t asdads6495/{service}:latest .`
- Push: `docker push asdads6495/{service}:latest`

**Registry**: Docker Hub (asdads6495 account)

---

## `scripts/` Directory (Utilities)

**Purpose**: Helper scripts for deployment, monitoring, etc.

**Pattern**: `{verb}-{noun}.sh`

**Common Scripts**:
- `deploy-jobs.sh` — Run all Nomad jobs
- `health-check.sh` — Verify cluster readiness
- `backup-db.sh` — RDS snapshot utilities
- (Others TBD based on project needs)

---

## `docs/` Directory (Documentation)

**Total**: 2,927 LOC across 5 files

**Files**:

| File | LOC | Purpose |
|------|-----|---------|
| `system-architecture.md` | 476 | Infrastructure layers, data flow, HA |
| `deployment-guide.md` | 639 | Step-by-step deployment with troubleshooting |
| `code-standards.md` | 809 | Terraform, HCL, Bash, Docker conventions |
| `consul-role-overview.md` | 556 | Service discovery, mTLS, health checks |
| `secrets-management-flow.md` | 447 | Vault, dynamic creds, KV v2, policies |

**Design**: Modular docs—each addresses one aspect; cross-referenced via "See also" sections.

---

## File Metrics

### Code Distribution

| Category | Files | LOC | Notes |
|----------|-------|-----|-------|
| Terraform | ~22 | 1,500+ | Across 4 stacks (base-infra, cluster, data, cdn) |
| Packer | 3 | 200+ | AMI build definition + variables |
| HCL Config | 4 | 120+ | Nomad, Consul, Vault, Consul Template |
| Nomad Jobs | 6 | 200+ | WordPress, Laravel, Nginx, Drone (server, runner, vault) |
| Vault Scripts | 1 | 100+ | Initialization script |
| Documentation | 6 | 2,927 | Comprehensive guides + architecture |
| **TOTAL** | **~42** | **~4,947** | Production-ready codebase |

### Terraform Breakdown

```
infra/stacks/
├── base-infra/      ~450 LOC (VPC, security, KMS, DNS)
├── cluster/         ~300 LOC (EC2, IAM)
├── data/            ~250 LOC (RDS, S3)
└── cdn/             ~200 LOC (CloudFront, ACM)
```

---

## Data Flows

### Job Deployment Flow

```
Developer edits job definition
    ↓
Validates with: nomad job validate
    ↓
Deploys with: nomad job run
    ↓
Nomad scheduler places task on eligible node
    ↓
EC2 instance pulls Docker image
    ↓
Nomad template injects Vault secrets
    ↓
Service registers with Consul
    ↓
Health checks pass
    ↓
Consul Template in Nginx notifies
    ↓
Nginx reloads; routes traffic
```

### Secret Lifecycle Flow

```
Nomad job starts
    ↓
Template reads: {{with secret "database/creds/wordpress"}}
    ↓
Nomad agent queries Vault
    ↓
Vault creates dynamic user in RDS
    ↓
Returns username + password (TTL: 1h)
    ↓
Environment variables set in container
    ↓
Nomad renews lease before expiry
    ↓
New credentials issued; container restarted
```

---

## Key Dependencies

### External Services

- **AWS**: EC2, RDS, S3, CloudFront, KMS, Route53, IAM
- **Docker Hub**: Image registry (asdads6495 account)

### Software Versions

- Terraform: >= 1.5
- Terragrunt: >= 0.48
- Nomad: >= 1.6
- Consul: >= 1.15
- Vault: >= 1.13
- Packer: >= 1.8
- AWS Provider: ~> 5.0
- Ubuntu: 22.04 LTS (Jammy)

### Internal References

- Terraform modules: Referenced via `source = "../../../stacks/{module}/"`
- Terragrunt dependencies: Declared via `dependencies { paths = [...] }`
- Nomad service discovery: Via `service { name = "..." }`
- Vault integration: Via `vault { policies = [...] }`
- Consul Connect: Via `connect { sidecar_service { ... } }`

---

## Security Architecture

**Layers**:
1. **Network** — Security groups restrict ports; private subnets isolate workloads
2. **Secrets** — Vault manages all credentials; dynamic rotation for databases
3. **Service Mesh** — Consul Connect mTLS encrypts inter-service traffic
4. **Access Control** — Consul Intentions enforce allow/deny rules
5. **Infrastructure** — IAM roles restrict EC2 permissions; KMS encrypts secrets

---

## Deployment Checklist

Before deploying, ensure:

- [ ] AWS account + credentials configured
- [ ] Terraform, Terragrunt, Packer, Nomad CLI installed
- [ ] SSH key in AWS (for optional direct access)
- [ ] Docker account (asdads6495) login for pushing images

**Deployment Steps**:
1. Build AMI (Packer) — `packer build ...`
2. Deploy base infra (Terraform) — `terragrunt apply`
3. Deploy data layer (RDS, S3) — `terragrunt apply`
4. Deploy cluster (EC2) — `terragrunt apply`
5. Initialize Vault — `./vault/init-vault.sh`
6. Deploy CDN (CloudFront) — `terragrunt apply`
7. Run Nomad jobs — `nomad job run ...`

**Total Deployment Time**: ~30-40 minutes

---

## File Size Distribution

| Type | Count | Total LOC | Avg LOC/File |
|------|-------|-----------|--------------|
| Terraform | 22 | 1,500 | 68 |
| HCL/Packer | 7 | 350 | 50 |
| Nomad Jobs | 6 | 250 | 42 |
| Scripts | 1 | 100+ | 100+ |
| Documentation | 6 | 2,927 | 488 |

**Note**: Terraform files under 200 LOC (modular); largest is code-standards.md at 809 LOC (informational, not code).

---

## Maintenance Notes

- **Terraform State**: S3 backend `nomad-infra-tfstate-dev`, auto-managed by Terragrunt
- **Backups**: RDS automated (7-day retention), S3 versioning enabled
- **Logs**: CloudWatch integration (EC2 logs forwarded)
- **Monitoring**: Nomad UI, Consul UI, Vault UI available on port access
- **Secrets Rotation**: DB credentials auto-rotate hourly; manual for static secrets
- **High Availability**: 3-node Raft cluster (Nomad, Consul, Vault); survives 1 node failure

---

## Related Documentation

- [System Architecture](./system-architecture.md) — Detailed technical design
- [Deployment Guide](./deployment-guide.md) — Step-by-step instructions
- [Code Standards](./code-standards.md) — Naming conventions, best practices
- [Consul Role Overview](./consul-role-overview.md) — Service discovery details
- [Secrets Management Flow](./secrets-management-flow.md) — Vault architecture details

---

**Last Updated**: 2026-05-14  
**Project Status**: Production-Ready  
**Maintenance**: Actively maintained
