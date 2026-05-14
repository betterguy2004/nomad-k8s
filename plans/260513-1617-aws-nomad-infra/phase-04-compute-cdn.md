---
phase: 4
title: "Compute & CDN"
status: complete
priority: P1
effort: "3h"
dependencies: [2, 3]
---

# Phase 4: Compute & CDN

## Overview

Deploy 3 EC2 instances using the Packer AMI with user-data bootstrap, IAM roles, and CloudFront distribution with ACM certificate.

**Reference:** [HashiCorp Official hashistack.tf](https://github.com/hashicorp/nomad/blob/main/terraform/aws/modules/hashistack/hashistack.tf)

## Requirements

**Functional:**
- 3× t3.medium EC2 in **public subnet** using Packer AMI (cost optimization)
- User-data configures Consul join, Vault address, Nomad cluster
- IAM role with KMS, EC2 describe, S3 access
- CloudFront with S3 (media) and app origin
- ACM wildcard certificate for domain

**Non-functional:**
- Instances in same AZ (single AZ design)
- CloudFront price class: PriceClass_100 (US, Canada, Europe)
- Public IPs for direct internet access (no NAT Gateway needed)

## Architecture

```
Compute:
┌─────────────────────────────────────────────────┐
│ Private Subnet                                   │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐      │
│  │ node-1    │ │ node-2    │ │ node-3    │      │
│  │ t3.medium │ │ t3.medium │ │ t3.medium │      │
│  │ Nomad     │ │ Nomad     │ │ Nomad     │      │
│  │ Consul    │ │ Consul    │ │ Consul    │      │
│  │ Vault     │ │ Vault     │ │ Vault     │      │
│  └───────────┘ └───────────┘ └───────────┘      │
└─────────────────────────────────────────────────┘

CDN:
Internet → CloudFront → ┬→ S3 (media/*)
                        └→ ALB/Nginx (default)
```

## Related Code Files

**Create:**
- `infra/stacks/cluster/main.tf`
- `infra/stacks/cluster/variables.tf`
- `infra/stacks/cluster/outputs.tf`
- `infra/stacks/cluster/ec2.tf`
- `infra/stacks/cluster/iam.tf`
- `infra/stacks/cluster/user-data.tftpl`
- `infra/stacks/cdn/main.tf`
- `infra/stacks/cdn/variables.tf`
- `infra/stacks/cdn/outputs.tf`
- `infra/stacks/cdn/cloudfront.tf`
- `infra/stacks/cdn/acm.tf`
- `infra/environments/dev/cluster/terragrunt.hcl`
- `infra/environments/dev/cdn/terragrunt.hcl`

## Implementation Steps

### Cluster Stack

1. **Create IAM role (iam.tf)**
   ```hcl
   resource "aws_iam_role" "nomad_cluster" {
     name = "nomad-cluster-role-dev"
     assume_role_policy = jsonencode({
       Version = "2012-10-17"
       Statement = [{
         Action = "sts:AssumeRole"
         Effect = "Allow"
         Principal = { Service = "ec2.amazonaws.com" }
       }]
     })
   }
   
   resource "aws_iam_role_policy" "nomad_cluster" {
     name = "nomad-cluster-policy"
     role = aws_iam_role.nomad_cluster.id
     policy = jsonencode({
       Version = "2012-10-17"
       Statement = [
         {
           Effect = "Allow"
           Action = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
           Resource = var.kms_key_arn
         },
         {
           Effect = "Allow"
           Action = ["ec2:DescribeInstances", "ec2:DescribeTags"]
           Resource = "*"
         },
         {
           Effect = "Allow"
           Action = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
           Resource = "${var.s3_bucket_arn}/*"
         }
       ]
     })
   }
   
   resource "aws_iam_instance_profile" "nomad_cluster" {
     name = "nomad-cluster-profile-dev"
     role = aws_iam_role.nomad_cluster.name
   }
   ```

2. **Create user-data template (user-data.tftpl)** - HashiCorp style
   ```bash
   #!/usr/bin/env bash
   set -e
   
   exec > >(sudo tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
   
   # Call the server bootstrap script (copied during Packer build)
   sudo bash /ops/shared/scripts/server.sh \
     "aws" \
     "${server_count}" \
     "provider=aws tag_key=ConsulAutoJoin tag_value=${cluster_name}" \
     "${region}" \
     "${kms_key_id}"
   ```
   
   The `server.sh` script (from Phase 1 Packer build) handles:
   - Getting instance IP from metadata service
   - Configuring Consul with auto-join tags
   - Configuring Vault with KMS auto-unseal
   - Configuring Nomad with server + client mode
   - Starting services in correct order

3. **Create EC2 instances (ec2.tf)** - HashiCorp style with auto-join tags
   ```hcl
   variable "retry_join" {
     type = map(string)
     default = {
       provider  = "aws"
       tag_key   = "ConsulAutoJoin"
       tag_value = "auto-join"
     }
   }
   
   resource "aws_instance" "nomad_cluster" {
     count = 3
     
     ami           = var.ami_id
     instance_type = "t3.medium"
     subnet_id     = var.public_subnet_id  # PUBLIC subnet (no NAT needed)
     
     vpc_security_group_ids      = [var.cluster_security_group_id]
     iam_instance_profile        = aws_iam_instance_profile.nomad_cluster.name
     associate_public_ip_address = true  # Auto-assign public IP
     
     user_data = templatefile("${path.module}/user-data.tftpl", {
       cluster_name = var.retry_join.tag_value
       server_count = 3
       region       = var.aws_region
       kms_key_id   = var.kms_key_id
     })
     
     # Tags for Consul auto-join (HashiCorp pattern)
     tags = merge(var.common_tags, {
       Name = "nomad-node-${count.index + 1}"
       "${var.retry_join.tag_key}" = var.retry_join.tag_value
     })
     
     root_block_device {
       volume_type           = "gp3"
       volume_size           = 30
       delete_on_termination = true
     }
   }
   
   # Output public IPs for access
   output "node_public_ips" {
     value = aws_instance.nomad_cluster[*].public_ip
   }
   ```
   
   > **Note:** Instances in public subnet with public IPs. Admin ports secured via Security Group (allowed_cidr).

### CDN Stack

> **IMPORTANT:** ACM certificates for CloudFront MUST be in us-east-1 (AWS requirement).
> Infrastructure runs in us-west-1, but ACM uses a provider alias for us-east-1.

4. **Create provider aliases (main.tf)**
   ```hcl
   # infra/stacks/cdn/main.tf
   terraform {
     required_providers {
       aws = {
         source  = "hashicorp/aws"
         version = "~> 5.0"
       }
     }
   }
   
   # Default provider - us-west-1 (inherited from root)
   provider "aws" {
     region = var.aws_region  # us-west-1
   }
   
   # ACM for CloudFront MUST be us-east-1
   provider "aws" {
     alias  = "us_east_1"
     region = "us-east-1"
   }
   ```

5. **Create ACM certificate (acm.tf)**
   ```hcl
   resource "aws_acm_certificate" "main" {
     provider          = aws.us_east_1  # CloudFront requires us-east-1
     domain_name       = var.domain_name
     subject_alternative_names = ["*.${var.domain_name}"]
     validation_method = "DNS"
   }
   
   resource "aws_route53_record" "acm_validation" {
     for_each = {
       for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => dvo
     }
     
     zone_id = var.route53_zone_id
     name    = each.value.resource_record_name
     type    = each.value.resource_record_type
     records = [each.value.resource_record_value]
     ttl     = 60
   }
   
   resource "aws_acm_certificate_validation" "main" {
     provider                = aws.us_east_1
     certificate_arn         = aws_acm_certificate.main.arn
     validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
   }
   ```

5. **Create CloudFront distribution (cloudfront.tf)**
   ```hcl
   resource "aws_cloudfront_distribution" "main" {
     enabled             = true
     default_root_object = "index.html"
     aliases             = [var.domain_name, "*.${var.domain_name}"]
     price_class         = "PriceClass_100"
     
     # S3 origin for media
     origin {
       domain_name = var.s3_bucket_regional_domain_name
       origin_id   = "S3Media"
       
       s3_origin_config {
         origin_access_identity = var.cloudfront_oai_path
       }
     }
     
     # App origin (placeholder - will point to Nginx)
     origin {
       domain_name = var.app_origin_domain  # EC2 private IP or internal LB
       origin_id   = "AppOrigin"
       
       custom_origin_config {
         http_port              = 80
         https_port             = 443
         origin_protocol_policy = "http-only"
         origin_ssl_protocols   = ["TLSv1.2"]
       }
     }
     
     # Media path behavior
     ordered_cache_behavior {
       path_pattern     = "/media/*"
       target_origin_id = "S3Media"
       allowed_methods  = ["GET", "HEAD"]
       cached_methods   = ["GET", "HEAD"]
       
       forwarded_values {
         query_string = false
         cookies { forward = "none" }
       }
       
       viewer_protocol_policy = "redirect-to-https"
     }
     
     # Default behavior (app)
     default_cache_behavior {
       target_origin_id       = "AppOrigin"
       allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
       cached_methods         = ["GET", "HEAD"]
       
       forwarded_values {
         query_string = true
         headers      = ["Host", "Authorization"]
         cookies { forward = "all" }
       }
       
       viewer_protocol_policy = "redirect-to-https"
     }
     
     viewer_certificate {
       acm_certificate_arn      = aws_acm_certificate_validation.main.certificate_arn
       ssl_support_method       = "sni-only"
       minimum_protocol_version = "TLSv1.2_2021"
     }
     
     restrictions {
       geo_restriction { restriction_type = "none" }
     }
   }
   ```

6. **Create Route53 A record**
   ```hcl
   resource "aws_route53_record" "main" {
     zone_id = var.route53_zone_id
     name    = var.domain_name
     type    = "A"
     
     alias {
       name                   = aws_cloudfront_distribution.main.domain_name
       zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
       evaluate_target_health = false
     }
   }
   ```

7. **Apply stacks**
   ```bash
   cd infra/environments/dev/cluster
   terragrunt apply
   
   cd ../cdn
   terragrunt apply
   ```

## Success Criteria

- [ ] 3 EC2 instances running with correct tags
- [ ] Consul cluster formed (3 servers)
- [ ] Vault nodes recognize each other
- [ ] Nomad cluster formed (3 servers/clients)
- [ ] ACM certificate validated
- [ ] CloudFront distribution deployed
- [ ] Route53 A record points to CloudFront

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Consul cluster fails to form | Check security group allows 8300-8302 |
| ACM validation timeout | Ensure Route53 zone NS delegated |
| CloudFront deploy time (15-20min) | Run early, plan for wait |
