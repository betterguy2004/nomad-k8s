# AWS Nomad Infrastructure Design

**Date:** 2026-05-13  
**Status:** Approved  
**Type:** Infrastructure + CI/CD

---

## Problem Statement

Build AWS infrastructure using Terraform + Terragrunt to run WordPress and Laravel on Nomad cluster with:
- Full HashiCorp stack (Nomad, Consul, Vault)
- Production-grade security (mTLS, dynamic secrets)
- CI/CD pipeline with Drone
- CDN and DNS management

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                           AWS Cloud                                  │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    VPC (10.0.0.0/16)                         │   │
│  │  ┌────────────────────┐  ┌────────────────────────────────┐  │   │
│  │  │   Public Subnet    │  │      Private Subnet            │  │   │
│  │  │   10.0.1.0/24      │  │      10.0.2.0/24               │  │   │
│  │  │  ┌──────────────┐  │  │  ┌─────────────────────────┐   │  │   │
│  │  │  │ NAT Gateway  │  │  │  │   Nomad/Consul/Vault    │   │  │   │
│  │  │  └──────────────┘  │  │  │   Cluster (3× t3.med)   │   │  │   │
│  │  └────────────────────┘  │  │   [WP] [Laravel] [Drone]│   │  │   │
│  │                          │  └─────────────────────────┘   │  │   │
│  │                          │  ┌─────────────────────────┐   │  │   │
│  │                          │  │  RDS MySQL 8.0 (micro)  │   │  │   │
│  │                          │  └─────────────────────────┘   │  │   │
│  │                          └────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────┘   │
│  [Route53] → [CloudFront] → [S3 OAI]    [KMS - Vault unseal]       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Decisions Summary

| Component | Decision | Rationale |
|-----------|----------|-----------|
| Terragrunt | Component-based stacks | Logical grouping, clear dependencies |
| Bootstrap | Packer AMI + user-data | Fast boot, reproducible images |
| HA Level | Single AZ | Dev environment, cost optimization |
| Compute | 3× t3.medium | Budget-friendly, sufficient for dev |
| Vault | KMS auto-unseal | Zero-touch operation, production-grade |
| Consul | Full Connect (mTLS) | Service mesh security |
| RDS | db.t3.micro | Free tier eligible |
| S3 | Private + CloudFront OAI | Secure media delivery |
| Load Balancer | Nginx + Consul Template | Auto-discovery, familiar tooling |
| CI/CD | Drone on Nomad | Lightweight, GitHub integration |
| Registry | Docker Hub | Simple setup, public images |
| Domain | `hungpq.io.vn` | User's domain |

---

## Project Structure

```
nomad-k8s/
├── infra/
│   ├── stacks/
│   │   ├── base-infra/          # VPC, SGs, Route53, KMS
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── data/                # RDS, S3
│   │   ├── cluster/             # EC2 ASG, IAM roles
│   │   └── cdn/                 # CloudFront, ACM
│   ├── packer/
│   │   ├── nomad-cluster.pkr.hcl
│   │   └── scripts/
│   │       ├── install-nomad.sh
│   │       ├── install-consul.sh
│   │       └── install-vault.sh
│   └── environments/
│       └── dev/
│           ├── terragrunt.hcl
│           ├── base-infra/terragrunt.hcl
│           ├── data/terragrunt.hcl
│           ├── cluster/terragrunt.hcl
│           └── cdn/terragrunt.hcl
├── jobs/
│   ├── system/
│   │   ├── nginx-lb.nomad.hcl
│   │   ├── consul-template.nomad.hcl
│   │   ├── drone-server.nomad.hcl
│   │   └── drone-runner.nomad.hcl
│   ├── wordpress.nomad.hcl
│   ├── laravel.nomad.hcl
│   └── vars/dev.vars
├── docker/
│   ├── wordpress/
│   │   ├── Dockerfile
│   │   └── .drone.yml
│   └── laravel/
│       ├── Dockerfile
│       ├── nginx.conf
│       └── .drone.yml
├── vault/
│   ├── policies/
│   │   ├── wordpress.hcl
│   │   ├── laravel.hcl
│   │   └── drone.hcl
│   └── setup/
│       ├── database-secrets.sh
│       └── drone-secrets.sh
└── scripts/
    ├── deploy-infra.sh
    └── deploy-jobs.sh
```

---

## Component Details

### 1. Networking (base-infra)

- VPC: 10.0.0.0/16
- Public subnet: 10.0.1.0/24 (NAT GW, bastion if needed)
- Private subnet: 10.0.2.0/24 (EC2, RDS)
- Single AZ deployment
- Security groups:
  - `nomad-cluster-sg`: internal cluster traffic, Consul/Nomad ports
  - `rds-sg`: MySQL 3306 from cluster only
  - `alb-sg`: 80/443 from internet

### 2. Compute (cluster)

- 3× t3.medium EC2 instances
- Packer AMI with pre-installed:
  - Nomad 1.7+
  - Consul 1.18+
  - Vault 1.15+
  - Docker CE
  - Nginx
  - Consul Template
- User-data for runtime config (Consul join, Vault address)
- IAM role with:
  - KMS decrypt (Vault auto-unseal)
  - EC2 describe (Consul auto-join)
  - S3 access (media uploads)

### 3. Data Layer

**RDS MySQL 8.0:**
- Instance: db.t3.micro
- Private subnet only
- Vault database secrets engine for dynamic creds
- Automated backups enabled

**S3 Bucket:**
- Private access
- CloudFront OAI for distribution
- Lifecycle rules for cost optimization

### 4. CDN & DNS

**Route53:**
- Hosted zone for `hungpq.io.vn`
- A record → CloudFront distribution
- Health checks optional

**CloudFront:**
- Origins: S3 (media), Nginx LB (app)
- ACM certificate (DNS validation)
- Cache behaviors per path pattern

**ACM:**
- Wildcard cert: `*.hungpq.io.vn`
- DNS validation via Route53

### 5. Service Mesh (Consul Connect)

- mTLS between all services
- Intentions:
  - wordpress → mysql (allow)
  - laravel → mysql (allow)
  - nginx → wordpress (allow)
  - nginx → laravel (allow)
  - drone-runner → nomad (allow)

### 6. Secrets Management (Vault)

**Auto-unseal:**
- KMS key in same region
- IAM role attached to EC2 instances

**Secrets Engines:**
- `database/` - MySQL dynamic creds
- `secret/` - KV v2 for static secrets

**Policies:**
- `wordpress` - read database/creds/wordpress
- `laravel` - read database/creds/laravel  
- `drone` - read secret/data/drone

### 7. Load Balancing

**Nginx (Nomad system job):**
- Runs on all nodes
- Consul Template generates upstream config
- SSL termination at CloudFront

**Consul Template:**
- Watches Consul catalog
- Regenerates nginx.conf on service changes
- Triggers nginx reload

### 8. CI/CD (Drone)

**Drone Server:**
- Nomad job, single instance
- GitHub OAuth app integration
- Vault secrets extension enabled
- SQLite database (persistent volume)

**Drone Runner:**
- Nomad system job (all nodes)
- Docker executor
- Auto-scales with cluster

**Pipelines:**
```
GitHub Push → Webhook → Drone Server
                           │
                           ▼
                     Drone Runner
                     ├─ Clone repo
                     ├─ Build Docker image
                     ├─ Push to Docker Hub
                     └─ nomad job run
```

---

## Deployment Flow

```
Phase 1: Packer Build
└─→ packer build infra/packer/nomad-cluster.pkr.hcl

Phase 2: Infrastructure (Terragrunt)
└─→ cd infra/environments/dev
└─→ terragrunt run-all apply
    ├─ base-infra (VPC, KMS, Route53)
    ├─ data (RDS, S3)
    ├─ cluster (EC2 ASG)
    └─ cdn (CloudFront, ACM)

Phase 3: HashiCorp Setup
└─→ vault operator init (get root token)
└─→ vault/setup/database-secrets.sh
└─→ vault/setup/drone-secrets.sh
└─→ consul intention create...

Phase 4: System Jobs
└─→ nomad job run jobs/system/nginx-lb.nomad.hcl
└─→ nomad job run jobs/system/consul-template.nomad.hcl
└─→ nomad job run jobs/system/drone-server.nomad.hcl
└─→ nomad job run jobs/system/drone-runner.nomad.hcl

Phase 5: Application Jobs
└─→ nomad job run jobs/wordpress.nomad.hcl
└─→ nomad job run jobs/laravel.nomad.hcl

Phase 6: CI/CD Activation
└─→ Configure GitHub webhook
└─→ Activate repos in Drone UI
└─→ Test pipeline trigger
```

---

## Cost Estimate (Monthly)

| Resource | Spec | Est. Cost |
|----------|------|-----------|
| EC2 (3×) | t3.medium | ~$90 |
| RDS | db.t3.micro | Free tier / ~$15 |
| ~~NAT Gateway~~ | ~~Single AZ~~ | ~~$32~~ **REMOVED** |
| S3 | Minimal storage | ~$1 |
| CloudFront | Basic usage | ~$5 |
| Route53 | Hosted zone | ~$0.50 |
| KMS | 1 key | ~$1 |
| **Total** | | **~$100-115/mo** |

> **Cost Optimization:** NAT Gateway removed. EC2 in public subnet with public IPs (learning env).

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Single AZ failure | Full outage | Accept for dev; multi-AZ for prod |
| t3 burst credits exhaustion | Performance degradation | Monitor CloudWatch; upgrade to m5 if needed |
| Vault manual init | Operational overhead | Document init procedure; automate post-deploy |
| Docker Hub rate limits | Build failures | Consider ECR for high-volume builds |
| Consul Connect complexity | Debug difficulty | Start with service discovery only; add mTLS incrementally |

---

## Success Criteria

- [ ] Packer AMI builds successfully
- [ ] Terragrunt deploys all stacks without errors
- [ ] Vault auto-unseals after EC2 restart
- [ ] Consul cluster forms with 3 nodes
- [ ] WordPress accessible via CloudFront URL
- [ ] Laravel accessible via CloudFront URL
- [ ] Drone builds triggered on GitHub push
- [ ] Drone deploys to Nomad automatically
- [ ] RDS credentials rotate via Vault
- [ ] S3 media accessible via CloudFront OAI

---

## Next Steps

1. Create detailed implementation plan with phases
2. Set up AWS account/credentials
3. Begin with Packer AMI build
4. Progress through Terragrunt stacks
5. Configure HashiCorp tools
6. Deploy workloads
7. Activate CI/CD pipeline

---

## Unresolved Questions

1. ~~**Domain transfer/delegation**~~: Domain `hungpq.io.vn` - cần delegate NS records từ registrar sang Route53
2. **Docker Hub credentials**: Existing account or create new?
3. **GitHub OAuth app**: Which GitHub org/user owns it?
4. **Backup strategy**: RDS snapshots frequency? S3 versioning enabled?
5. **Monitoring**: CloudWatch only or add Prometheus/Grafana?
