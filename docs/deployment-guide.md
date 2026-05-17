# Deployment Guide

Step-by-step instructions for deploying the Nomad infrastructure from scratch.

## Pre-deployment Checklist

- [ ] AWS account with permissions (EC2, RDS, S3, KMS, Route53, IAM, CloudFront)
- [ ] AWS CLI configured: `aws sts get-caller-identity` (should show your account)
- [ ] Terraform 1.5+: `terraform --version`
- [ ] Terragrunt 0.48+: `terragrunt --version`
- [ ] Packer 1.8+: `packer --version`
- [ ] Nomad CLI 1.6+: `nomad --version`
- [ ] Consul CLI 1.15+: `consul --version`
- [ ] Vault CLI 1.13+: `vault --version`
- [ ] Docker installed locally (for pushing test images)
- [ ] SSH key in AWS: `aws ec2 describe-key-pairs` (note the name)

## Environment Setup

Create `.env` file in project root (never commit):

```bash
# AWS Configuration
export AWS_REGION=us-west-1
export AWS_PROFILE=default  # or your named profile

# Terraform Variables
export TF_VAR_environment=dev
export TF_VAR_app_name=nomad-k8s
export TF_VAR_aws_region=us-west-1
export TF_VAR_availability_zones='["us-west-1a", "us-west-1b"]'

# Packer Variables
export PKR_VAR_aws_region=us-west-1
export PKR_VAR_environment=dev

# Nomad/Consul/Vault Access (populated after deployment)
export NOMAD_ADDR=http://<cluster-lb-ip>:4646
export CONSUL_HTTP_ADDR=http://<cluster-lb-ip>:8500
export VAULT_ADDR=http://<cluster-lb-ip>:8200
```

Load into shell:
```bash
source .env
```

## Step 1: Build AMI with Packer

This creates a reusable machine image with Nomad, Consul, Vault, and Docker pre-installed.

```bash
cd infra/packer

# Validate configuration
packer validate -var-file=dev.pkrvars.hcl nomad-cluster.pkr.hcl

# Build image (takes ~10 minutes)
packer build -var-file=dev.pkrvars.hcl nomad-cluster.pkr.hcl
```

Output:
```
Build 'amazon-ebs.nomad-cluster' finished after 10 minutes 23 seconds.

--> amazon-ebs.nomad-cluster: AMIs were created:
us-west-1: ami-0c8f4d8f8f8f8f8f8
```

**Note the AMI ID** — you'll reference it in the cluster step.

### Verify Image

```bash
aws ec2 describe-images --image-ids ami-0c8f4d8f8f8f8f8f8 --region us-west-1
```

## Step 2: Deploy Base Infrastructure

Creates VPC, subnets, security groups, KMS key, and Route53 zone.

```bash
cd infra/environments/dev/base-infra

# Review what will be created
terragrunt plan

# Apply (takes ~5 minutes)
terragrunt apply
```

**Outputs** (saved in Terraform state):
```
Outputs:
  vpc_id = "vpc-0c8f4d8f8f8f8f8f"
  private_subnet_ids = ["subnet-1", "subnet-2", "subnet-3"]
  public_subnet_ids = ["subnet-4", "subnet-5"]
  kms_key_id = "arn:aws:kms:us-west-1:123456789:key/..."
  security_group_nomad_id = "sg-0c8f4d8f8f8f8f8f"
  security_group_rds_id = "sg-0c8f4d8f8f8f8f8f"
```

### Verify Base Infrastructure

```bash
# Check VPC
aws ec2 describe-vpcs --filter "Name=tag:Name,Values=nomad-k8s-dev" --region us-west-1

# Check security groups
aws ec2 describe-security-groups --filter "Name=tag:Name,Values=nomad-*" --region us-west-1

# Check KMS key
aws kms list-keys --region us-west-1 | grep vault-unseal
```

## Step 3: Deploy Data Layer (RDS + S3)

Creates MySQL database and S3 buckets for media storage.

```bash
cd infra/environments/dev/data

# Review
terragrunt plan

# Apply (takes ~8 minutes for RDS)
terragrunt apply
```

**Outputs**:
```
Outputs:
  rds_endpoint = "nomad-k8s-dev.cxyz.us-west-1.rds.amazonaws.com"
  s3_bucket_media = "nomad-media-xxx-dev"
  s3_bucket_backups = "nomad-backups-xxx-dev"
```

**Save the RDS endpoint** — you'll need it later for Vault configuration.

### Verify RDS

```bash
# Wait for available status
aws rds describe-db-instances \
  --db-instance-identifier nomad-k8s-dev \
  --region us-west-1 \
  --query 'DBInstances[0].DBInstanceStatus'
# Expected: "available"

# Get endpoint
aws rds describe-db-instances \
  --db-instance-identifier nomad-k8s-dev \
  --region us-west-1 \
  --query 'DBInstances[0].Endpoint.Address'
```

### Verify S3 Buckets

```bash
aws s3 ls | grep nomad-media
aws s3 ls | grep nomad-backups
```

## Step 4: Deploy EC2 Cluster

Creates 3 EC2 instances (Nomad servers + Consul servers) that auto-join into a cluster.

```bash
cd infra/environments/dev/cluster

# Review
terragrunt plan

# Apply (takes ~15 minutes)
terragrunt apply
```

**Outputs**:
```
Outputs:
  instance_ids = ["i-0c8f4d8f", "i-0c8f4d8f", "i-0c8f4d8f"]
  private_ips = ["10.0.10.5", "10.0.11.5", "10.0.12.5"]
  load_balancer_dns = "nomad-cluster-nlb-xxx.elb.us-west-1.amazonaws.com"
```

**Save the load balancer DNS** — use this to access Nomad/Consul/Vault UIs.

### Verify Cluster Formation

Wait 2-3 minutes for services to start, then check:

```bash
# Get load balancer IP
LB_IP=$(aws ec2 describe-load-balancers \
  --load-balancer-names nomad-cluster-nlb \
  --region us-west-1 \
  --query 'LoadBalancerDescriptions[0].DNSName' \
  --output text)

# Check Nomad cluster
curl http://$LB_IP:4646/v1/status/leader

# Check Consul cluster
curl http://$LB_IP:8500/v1/agent/members

# Check Vault status
curl http://$LB_IP:8200/v1/sys/health
# Expected: "initialized": true, "sealed": false (auto-unsealed via KMS)
```

### SSH into Node (if needed)

```bash
# Get node IP
NODE_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=nomad-node-1" \
  --region us-west-1 \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

# SSH via bastion (requires AWS SSM Session Manager or bastion host)
# For now, verify via API instead of SSH
```

## Step 5: Initialize Vault & Nomad ACL

Set up Nomad ACL, Vault JWT auth (Workload Identity), and secrets.

### 5a. Set Environment Variables

```bash
# Required for vault-migration.sh
export VAULT_ADDR=https://<node-ip>:8200
export VAULT_TOKEN=<vault-root-token>
export NOMAD_NODES="<node1-ip> <node2-ip> <node3-ip>"
export SSH_KEY=/path/to/nomad-key.pem

# WordPress secrets (generate at https://api.wordpress.org/secret-key/1.1/salt/)
export WP_AUTH_KEY="..."
export WP_SECURE_AUTH_KEY="..."
export WP_LOGGED_IN_KEY="..."
export WP_NONCE_KEY="..."
export WP_AUTH_SALT="..."
export WP_SECURE_AUTH_SALT="..."
export WP_LOGGED_IN_SALT="..."
export WP_NONCE_SALT="..."
export WP_DB_HOST="<rds-endpoint>"
export WP_DB_USER="admin"
export WP_DB_PASSWORD="<rds-password>"
export WP_DB_NAME="wordpress"
```

### 5b. Run Vault Migration Script

```bash
cd scripts

# Deploy Nomad config with ACL + Workload Identity
./vault-migration.sh phase1-config
./vault-migration.sh phase1-restart

# Bootstrap Nomad ACL (SAVE THE TOKEN!)
ssh -i $SSH_KEY ubuntu@<node1-ip> 'nomad acl bootstrap'
export NOMAD_TOKEN=<bootstrap-token>

# Configure Vault JWT auth + store secrets
./vault-migration.sh vault-only
```

**Script does**:
1. Enables Nomad ACL system
2. Configures Workload Identity (JWT auth to Vault)
3. Creates `jwt-nomad` auth method in Vault
4. Creates `wordpress-secrets` and `drone-secrets` policies
5. Stores secrets in Vault KV v2

### 5c. Verify Setup

```bash
# Check Nomad JWKS endpoint
curl http://<node-ip>:4646/.well-known/jwks.json

# Check Vault JWT auth
vault read auth/jwt-nomad/config
vault read auth/jwt-nomad/role/nomad-workloads

# Check secrets
vault kv get secret/wordpress/keys
vault kv get secret/wordpress/db
```

## Step 6: Deploy CloudFront (Optional)

Creates CDN distribution for S3 media delivery.

```bash
cd infra/environments/dev/cdn

# Review
terragrunt plan

# Apply (takes ~2 minutes)
terragrunt apply
```

**Outputs**:
```
Outputs:
  cloudfront_domain_name = "d123.cloudfront.net"
  cloudfront_distribution_id = "E123ABC"
```

### Verify CloudFront

```bash
# Wait for distribution to be deployed (~5 minutes)
aws cloudfront get-distribution \
  --id E123ABC \
  --query 'Distribution.DistributionConfig.Enabled'
# Expected: true

# Test object access
curl https://d123.cloudfront.net/test-file.txt
# Expected: 403 (no objects yet, but CDN is working)
```

## Step 7: Deploy Nomad Jobs

Now orchestrate the applications.

### 7a. Deploy WordPress

```bash
cd jobs

# Validate job
nomad job validate wordpress.nomad.hcl

# Deploy (requires Nomad CLI access)
export NOMAD_ADDR=http://$LB_IP:4646
nomad job run wordpress.nomad.hcl

# Monitor
nomad job status wordpress
```

**Expected output**:
```
ID            = "wordpress"
Name          = "wordpress"
Submit Date   = 2026-05-14T10:30:00Z
Type          = "service"
Priority      = 50
Datacenters   = ["dc1"]
Status        = "running"
Periodic      = false
Parameterized = false

Summary
Task Group  Desired  Placed  Healthy  Unhealthy
wordpress   2        2       2        0
```

### 7b. Deploy Laravel

```bash
nomad job run laravel.nomad.hcl

# Monitor
nomad job status laravel
nomad alloc logs <alloc-id>  # Check migration output
```

### 7c. Deploy Nginx Load Balancer

```bash
nomad job run system/nginx-lb.nomad.hcl

# Monitor
nomad job status nginx-lb
nomad alloc logs <alloc-id> stdout  # Check nginx startup
```

### 7d. Deploy Drone CI/CD System

```bash
# Server
nomad job run system/drone-server.nomad.hcl

# Runner
nomad job run system/drone-runner.nomad.hcl

# Vault extension
nomad job run system/drone-vault.nomad.hcl

# Monitor
nomad job status drone-server
nomad job status drone-runner
nomad job status drone-vault
```

### Verify All Jobs

```bash
# List all jobs
nomad job list

# Check service discovery
export CONSUL_HTTP_ADDR=http://$LB_IP:8500
consul catalog services
# Expected: consul, nomad, wordpress, laravel, nginx-lb, drone-*

# Check service health
consul health checks wordpress
consul health checks laravel
```

## Step 8: Verify End-to-End

Test the complete flow.

### Access Nomad UI

```
http://<LB_IP>:4646
```
Expected: Nomad dashboard showing all jobs running.

### Access Consul UI

```
http://<LB_IP>:8500
```
Expected: Consul dashboard showing services, nodes, and health checks.

### Access Vault UI

```
http://<LB_IP>:8200
```
Login with root token (from `.vault-root-token`).

### Test Application Connectivity

```bash
# Get WordPress allocation
ALLOC_ID=$(nomad job allocs wordpress | grep running | head -1 | awk '{print $1}')

# Check WordPress environment
nomad alloc exec $ALLOC_ID env | grep WORDPRESS_

# Test MySQL connectivity inside container
nomad alloc exec $ALLOC_ID mysql -u$WORDPRESS_DB_USER -p$WORDPRESS_DB_PASSWORD \
  -h$WORDPRESS_DB_HOST -e "SELECT 1;"
# Expected: 1 (successful connection)
```

### Test Nginx Routing

```bash
# Get Nginx allocation
NGINX_ALLOC=$(nomad job allocs nginx-lb | grep running | head -1 | awk '{print $1}')

# Check generated config
nomad alloc exec $NGINX_ALLOC cat /etc/nginx/conf.d/upstreams.conf

# Should show:
# upstream wordpress {
#   server 10.0.10.x:9000;
#   server 10.0.11.x:9000;
# }
```

## Troubleshooting

### Cluster nodes won't join

**Symptom**: Only 1 node appears in `nomad node status`

**Diagnosis**:
```bash
# SSH into a node (via Systems Manager Session Manager or bastion)
consul members

# Check Consul logs
journalctl -u consul -f

# Check auto-join configuration
cat /opt/consul/config/consul.hcl | grep retry_join
```

**Solution**:
1. Verify EC2 tags: `aws ec2 describe-tags --filters "Name=resource-type,Values=instance"`
2. Verify IAM role has `ec2:DescribeTags` permission
3. Restart Consul: `systemctl restart consul`

### Vault is sealed

**Symptom**: `vault status` shows `Sealed = true`

**Diagnosis**:
```bash
vault status
# Check KMS key access
aws kms describe-key --key-id alias/vault-unseal-dev
```

**Solution**:
1. Verify KMS key exists and is accessible
2. Verify EC2 instance role has `kms:Decrypt` permission
3. Restart Vault: `systemctl restart vault`
4. Check logs: `journalctl -u vault -f`

### Jobs won't schedule

**Symptom**: `nomad job status <job>` shows `Status = pending`

**Diagnosis**:
```bash
# Check Nomad logs
nomad alloc logs <alloc-id>

# Check resource constraints
nomad node status
# Does cluster have enough CPU/memory?
```

**Solution**:
1. Reduce job resource requirements (edit `.nomad.hcl`)
2. Increase cluster size (add EC2 nodes via Terraform)
3. Check Consul health: `consul health service <service>`

### Services not discovered

**Symptom**: `consul catalog services` missing WordPress/Laravel

**Diagnosis**:
```bash
# Check Nomad service registration
nomad alloc logs <alloc-id> | grep service

# Check Consul directly
consul services register -name=test -port=8080
consul catalog services  # Should show "test"
```

**Solution**:
1. Verify job has `service { name = ... }` block
2. Check Nomad-Consul integration: `nomad server members`
3. Verify Consul connect: `consul connect ca get-config`

### Database credentials not working

**Symptom**: Job fails with `Can't connect to MySQL server`

**Diagnosis**:
```bash
# Check Vault database role
vault read database/creds/wordpress

# Check RDS connectivity from node
nomad alloc exec <alloc-id> mysql -uroot -ppassword \
  -h<rds-endpoint> -e "SELECT 1;"
```

**Solution**:
1. Verify RDS is `available`: `aws rds describe-db-instances --db-instance-identifier nomad-k8s-dev`
2. Verify security group allows access: Check RDS SG inbound rules
3. Verify Vault can connect to RDS: Check Vault logs

### CloudFront not working

**Symptom**: Objects in S3 not cached via CloudFront

**Diagnosis**:
```bash
# Check distribution status
aws cloudfront get-distribution --id <distribution-id> \
  --query 'Distribution.Status'

# Test origin access
aws s3 ls nomad-media-xxx-dev/

# Check cache behavior
aws cloudfront get-distribution-config --id <distribution-id> \
  --query 'DistributionConfig.CacheBehaviors'
```

**Solution**:
1. Wait for distribution to deploy (Status = "Deployed")
2. Verify origin S3 bucket exists and is accessible
3. Re-apply CloudFront config: `terragrunt apply`

## Cleanup (Destroy Infrastructure)

To tear down everything (use caution):

```bash
# Destroy jobs first (removes load on infrastructure)
nomad job stop wordpress
nomad job stop laravel
nomad job stop system/nginx-lb
nomad job stop system/drone-*

# Destroy infrastructure in reverse order
cd infra/environments/dev/cdn && terragrunt destroy
cd infra/environments/dev/cluster && terragrunt destroy
cd infra/environments/dev/data && terragrunt destroy
cd infra/environments/dev/base-infra && terragrunt destroy

# Deregister AMI (optional)
aws ec2 deregister-image --image-id ami-0c8f4d8f --region us-west-1
```

**Warning**: This deletes all data. Ensure backups are in place before destroying.

## Quick Reference Commands

```bash
# Cluster status
nomad node status
nomad job list
consul members
vault status

# Service discovery
consul catalog services
consul health service wordpress

# Logs
nomad alloc logs <alloc-id> stdout
nomad alloc logs <alloc-id> stderr
journalctl -u nomad -f
journalctl -u consul -f
journalctl -u vault -f

# Vault
vault secrets list
vault kv list secret/
vault read database/creds/wordpress

# Secrets in containers
nomad alloc exec <alloc-id> env | grep DB_
nomad alloc exec <alloc-id> env | grep VAULT_

# Restart services
nomad job stop <job>
nomad job run <job>

# Configuration
nomad job inspect <job>
consul kv get -recurse

# Debug Consul Template
nomad alloc exec <alloc-id> cat /etc/nginx/conf.d/upstreams.conf
```

---

See also: [System Architecture](./system-architecture.md), [Consul Role Overview](./consul-role-overview.md), [Secrets Management Flow](./secrets-management-flow.md)
