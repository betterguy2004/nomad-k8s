---
phase: 3
title: "Data & Storage"
status: complete
priority: P1
effort: "2h"
dependencies: [2]
---

# Phase 3: Data & Storage

## Overview

Create RDS MySQL 8.0 instance in private subnet and S3 bucket for WordPress media with CloudFront OAI access.

## Requirements

**Functional:**
- RDS MySQL 8.0, db.t3.micro, private subnet
- Master credentials stored in AWS Secrets Manager (Vault will manage app creds)
- S3 bucket private, CloudFront OAI only
- Lifecycle rules for S3 cost optimization

**Non-functional:**
- Automated backups enabled (7 days retention)
- Encryption at rest for both RDS and S3

## Architecture

```
Data Layer:
┌─────────────────────────────────────────┐
│ Private Subnet                          │
│  ┌─────────────────────────────────┐    │
│  │ RDS MySQL 8.0 (db.t3.micro)     │    │
│  │ - Storage: 20GB gp3             │    │
│  │ - Backups: 7 days               │    │
│  │ - Encryption: AWS managed key   │    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘

S3 Bucket:
┌─────────────────────────────────────────┐
│ nomad-media-{account-id}-dev            │
│ - Versioning: enabled                   │
│ - Public access: blocked                │
│ - OAI: CloudFront only                  │
│ - Lifecycle: IA after 30 days           │
└─────────────────────────────────────────┘
```

## Related Code Files

**Create:**
- `infra/stacks/data/main.tf`
- `infra/stacks/data/variables.tf`
- `infra/stacks/data/outputs.tf`
- `infra/stacks/data/rds.tf`
- `infra/stacks/data/s3.tf`
- `infra/environments/dev/data/terragrunt.hcl`

## Implementation Steps

1. **Create RDS subnet group**
   - Include private subnet (single AZ for dev)
   - Name: nomad-rds-subnet-group-dev

2. **Create RDS parameter group**
   - Family: mysql8.0
   - Parameters: character_set_server=utf8mb4, collation_server=utf8mb4_unicode_ci

3. **Create RDS instance (rds.tf)**
   ```hcl
   resource "aws_db_instance" "mysql" {
     identifier     = "nomad-mysql-dev"
     engine         = "mysql"
     engine_version = "8.0"
     instance_class = "db.t3.micro"
     
     allocated_storage     = 20
     storage_type          = "gp3"
     storage_encrypted     = true
     
     db_name  = "nomad"
     username = "admin"
     password = random_password.rds_master.result
     
     vpc_security_group_ids = [var.rds_security_group_id]
     db_subnet_group_name   = aws_db_subnet_group.main.name
     
     backup_retention_period = 7
     backup_window          = "03:00-04:00"
     maintenance_window     = "Mon:04:00-Mon:05:00"
     
     skip_final_snapshot = true  # Dev only
     
     tags = var.common_tags
   }
   ```

4. **Store master password in Secrets Manager**
   ```hcl
   resource "aws_secretsmanager_secret" "rds_master" {
     name = "nomad/rds/master-password"
   }
   
   resource "aws_secretsmanager_secret_version" "rds_master" {
     secret_id     = aws_secretsmanager_secret.rds_master.id
     secret_string = jsonencode({
       username = aws_db_instance.mysql.username
       password = random_password.rds_master.result
       host     = aws_db_instance.mysql.address
       port     = aws_db_instance.mysql.port
     })
   }
   ```

5. **Create S3 bucket (s3.tf)**
   ```hcl
   resource "aws_s3_bucket" "media" {
     bucket = "nomad-media-${data.aws_caller_identity.current.account_id}-dev"
   }
   
   resource "aws_s3_bucket_public_access_block" "media" {
     bucket = aws_s3_bucket.media.id
     
     block_public_acls       = true
     block_public_policy     = true
     ignore_public_acls      = true
     restrict_public_buckets = true
   }
   
   resource "aws_s3_bucket_versioning" "media" {
     bucket = aws_s3_bucket.media.id
     versioning_configuration {
       status = "Enabled"
     }
   }
   ```

6. **Create CloudFront OAI**
   ```hcl
   resource "aws_cloudfront_origin_access_identity" "media" {
     comment = "OAI for nomad media bucket"
   }
   ```

7. **Create S3 bucket policy for OAI**
   ```hcl
   resource "aws_s3_bucket_policy" "media" {
     bucket = aws_s3_bucket.media.id
     policy = jsonencode({
       Version = "2012-10-17"
       Statement = [{
         Sid       = "CloudFrontOAI"
         Effect    = "Allow"
         Principal = {
           AWS = aws_cloudfront_origin_access_identity.media.iam_arn
         }
         Action   = "s3:GetObject"
         Resource = "${aws_s3_bucket.media.arn}/*"
       }]
     })
   }
   ```

8. **Create S3 lifecycle rule**
   - Transition to IA after 30 days
   - Delete incomplete multipart uploads after 7 days

9. **Create Terragrunt wrapper**
   ```hcl
   # infra/environments/dev/data/terragrunt.hcl
   dependency "base_infra" {
     config_path = "../base-infra"
   }
   
   inputs = {
     private_subnet_id     = dependency.base_infra.outputs.private_subnet_id
     rds_security_group_id = dependency.base_infra.outputs.security_group_ids["rds"]
   }
   ```

10. **Apply**
    ```bash
    cd infra/environments/dev/data
    terragrunt apply
    ```

## Success Criteria

- [ ] RDS instance running and accessible from cluster SG
- [ ] Master password in Secrets Manager
- [ ] S3 bucket exists with public access blocked
- [ ] OAI created and bucket policy attached
- [ ] Lifecycle rules active
- [ ] Outputs: rds_endpoint, rds_port, s3_bucket_name, oai_id

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| RDS provisioning time (10-15min) | Run early in deployment |
| Free tier expiry | Monitor AWS billing alerts |
| Accidental data loss | skip_final_snapshot=false for prod |
