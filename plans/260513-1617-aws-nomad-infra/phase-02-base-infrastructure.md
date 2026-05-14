---
phase: 2
title: "Base Infrastructure"
status: complete
priority: P1
effort: "3h"
dependencies: [1]
---

# Phase 2: Base Infrastructure

## Overview

Create foundational AWS infrastructure using Terragrunt: VPC, subnets, security groups, KMS key for Vault auto-unseal, and Route53 hosted zone.

> **Cost Optimization:** No NAT Gateway (~$32/month saved). EC2 instances in public subnet with public IPs. RDS remains in private subnet (accessible via VPC internal routing).

## Requirements

**Functional:**
- VPC with public and private subnets in single AZ
- Public subnet: EC2 instances with public IPs + Internet Gateway
- Private subnet: RDS only (no internet access needed)
- Security groups for cluster, RDS traffic
- KMS key for Vault auto-unseal
- Route53 hosted zone for domain

**Non-functional:**
- Terragrunt DRY configuration
- All resources tagged with Environment, Project
- **No NAT Gateway** (cost optimization for learning env)

## Architecture

```
VPC (10.0.0.0/16)
├── Public Subnet (10.0.1.0/24)
│   ├── Internet Gateway
│   ├── Route Table → IGW
│   └── EC2 Instances (Nomad/Consul/Vault) ← Public IPs
└── Private Subnet (10.0.2.0/24)
    ├── Route Table → local only (no internet)
    └── RDS MySQL

NOTE: No NAT Gateway - EC2 in public subnet for cost savings

Security Groups:
├── nomad-cluster-sg
│   ├── 22 (SSH) from your IP only
│   ├── 80/443 (HTTP/S) from anywhere
│   ├── 4646-4648 (Nomad) from your IP + cluster-sg
│   ├── 8200 (Vault) from your IP + cluster-sg
│   ├── 8300-8302, 8500-8502 (Consul) from cluster-sg
│   └── All traffic from self (cluster internal)
└── rds-sg
    └── 3306 from cluster-sg only
```

## Related Code Files

**Create:**
- `infra/stacks/base-infra/main.tf`
- `infra/stacks/base-infra/variables.tf`
- `infra/stacks/base-infra/outputs.tf`
- `infra/stacks/base-infra/vpc.tf`
- `infra/stacks/base-infra/security-groups.tf`
- `infra/stacks/base-infra/kms.tf`
- `infra/stacks/base-infra/route53.tf`
- `infra/environments/dev/terragrunt.hcl` (root)
- `infra/environments/dev/base-infra/terragrunt.hcl`

## Implementation Steps

1. **Create Terragrunt root config**
   ```hcl
   # infra/environments/dev/terragrunt.hcl
   remote_state {
     backend = "s3"
     config = {
       bucket  = "nomad-infra-tfstate-dev"
       key     = "${path_relative_to_include()}/terraform.tfstate"
       region  = "us-west-1"  # Changed from us-east-1
       encrypt = true
     }
   }
   
   inputs = {
     environment = "dev"
     project     = "nomad-k8s"
     aws_region  = "us-west-1"  # Changed from us-east-1
   }
   ```

2. **Create VPC module (vpc.tf)**
   ```hcl
   # VPC
   resource "aws_vpc" "main" {
     cidr_block           = var.vpc_cidr
     enable_dns_hostnames = true
     enable_dns_support   = true
     tags = { Name = "${var.project}-vpc-${var.environment}" }
   }
   
   # Internet Gateway
   resource "aws_internet_gateway" "main" {
     vpc_id = aws_vpc.main.id
   }
   
   # Public Subnet (for EC2 - with public IPs)
   resource "aws_subnet" "public" {
     vpc_id                  = aws_vpc.main.id
     cidr_block              = var.public_subnet_cidr
     availability_zone       = var.availability_zone
     map_public_ip_on_launch = true  # Auto-assign public IPs
     tags = { Name = "${var.project}-public-${var.environment}" }
   }
   
   # Private Subnet (for RDS only - no internet)
   resource "aws_subnet" "private" {
     vpc_id            = aws_vpc.main.id
     cidr_block        = var.private_subnet_cidr
     availability_zone = var.availability_zone
     tags = { Name = "${var.project}-private-${var.environment}" }
   }
   
   # Public Route Table (→ IGW)
   resource "aws_route_table" "public" {
     vpc_id = aws_vpc.main.id
     route {
       cidr_block = "0.0.0.0/0"
       gateway_id = aws_internet_gateway.main.id
     }
   }
   
   resource "aws_route_table_association" "public" {
     subnet_id      = aws_subnet.public.id
     route_table_id = aws_route_table.public.id
   }
   
   # Private Route Table (local only - no NAT Gateway)
   resource "aws_route_table" "private" {
     vpc_id = aws_vpc.main.id
     # No route to internet - RDS doesn't need it
   }
   
   resource "aws_route_table_association" "private" {
     subnet_id      = aws_subnet.private.id
     route_table_id = aws_route_table.private.id
   }
   
   # NO NAT Gateway - cost savings for learning environment
   ```

3. **Create Security Groups (security-groups.tf)**
   ```hcl
   # Your public IP for restricted access
   variable "allowed_cidr" {
     description = "Your IP for SSH/admin access (e.g., 1.2.3.4/32)"
     type        = string
   }
   
   resource "aws_security_group" "nomad_cluster" {
     name        = "${var.project}-cluster-sg"
     description = "Nomad/Consul/Vault cluster"
     vpc_id      = aws_vpc.main.id
     
     # SSH - restricted to your IP
     ingress {
       from_port   = 22
       to_port     = 22
       protocol    = "tcp"
       cidr_blocks = [var.allowed_cidr]
       description = "SSH from allowed IP"
     }
     
     # HTTP/HTTPS - from anywhere (for web apps)
     ingress {
       from_port   = 80
       to_port     = 80
       protocol    = "tcp"
       cidr_blocks = ["0.0.0.0/0"]
     }
     ingress {
       from_port   = 443
       to_port     = 443
       protocol    = "tcp"
       cidr_blocks = ["0.0.0.0/0"]
     }
     
     # Nomad UI/API - restricted to your IP
     ingress {
       from_port   = 4646
       to_port     = 4648
       protocol    = "tcp"
       cidr_blocks = [var.allowed_cidr]
       description = "Nomad from allowed IP"
     }
     
     # Vault UI/API - restricted to your IP  
     ingress {
       from_port   = 8200
       to_port     = 8200
       protocol    = "tcp"
       cidr_blocks = [var.allowed_cidr]
       description = "Vault from allowed IP"
     }
     
     # Consul UI - restricted to your IP
     ingress {
       from_port   = 8500
       to_port     = 8500
       protocol    = "tcp"
       cidr_blocks = [var.allowed_cidr]
       description = "Consul UI from allowed IP"
     }
     
     # Cluster internal - all traffic between nodes
     ingress {
       from_port = 0
       to_port   = 0
       protocol  = "-1"
       self      = true
       description = "Cluster internal"
     }
     
     egress {
       from_port   = 0
       to_port     = 0
       protocol    = "-1"
       cidr_blocks = ["0.0.0.0/0"]
     }
   }
   
   resource "aws_security_group" "rds" {
     name        = "${var.project}-rds-sg"
     description = "RDS MySQL"
     vpc_id      = aws_vpc.main.id
     
     ingress {
       from_port       = 3306
       to_port         = 3306
       protocol        = "tcp"
       security_groups = [aws_security_group.nomad_cluster.id]
       description     = "MySQL from cluster only"
     }
   }
   ```
   
   > **Security Note:** Since EC2 is in public subnet, admin ports (Nomad/Vault/Consul) are restricted to `allowed_cidr` (your IP).

4. **Create KMS key (kms.tf)**
   - Symmetric key for Vault auto-unseal
   - Key policy allowing EC2 role to use for encrypt/decrypt
   - Alias: alias/vault-unseal-dev

5. **Create Route53 zone (route53.tf)**
   - Hosted zone for `hungpq.io.vn`
   - Output NS records for delegation

6. **Create outputs.tf**
   - vpc_id, public_subnet_id, private_subnet_id
   - security_group_ids (map)
   - kms_key_id, kms_key_arn
   - route53_zone_id, route53_nameservers

7. **Create Terragrunt wrapper**
   ```hcl
   # infra/environments/dev/base-infra/terragrunt.hcl
   include "root" {
     path = find_in_parent_folders()
   }
   
   terraform {
     source = "../../../stacks/base-infra"
   }
   
   inputs = {
     vpc_cidr            = "10.0.0.0/16"
     public_subnet_cidr  = "10.0.1.0/24"
     private_subnet_cidr = "10.0.2.0/24"
     availability_zone   = "us-west-1a"  # Changed from us-east-1a
     domain_name         = "hungpq.io.vn"
   }
   ```

8. **Apply infrastructure**
   ```bash
   cd infra/environments/dev/base-infra
   terragrunt init
   terragrunt plan
   terragrunt apply
   ```

## Success Criteria

- [ ] VPC created with correct CIDR
- [ ] NAT Gateway has EIP and routes traffic
- [ ] Security groups allow expected traffic patterns
- [ ] KMS key exists with correct alias
- [ ] Route53 zone created, NS records available
- [ ] All outputs exported for dependent stacks

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| S3 state bucket doesn't exist | Create bucket manually or use terragrunt create_before_destroy |
| EC2 public exposure | Restrict admin ports to your IP via `allowed_cidr` variable |
| IP changes | Update `allowed_cidr` when your IP changes, or use VPN/bastion later |
| Domain NS delegation delay | Plan for 24-48h DNS propagation |

> **Cost Saved:** ~$32/month by removing NAT Gateway (learning env tradeoff)
