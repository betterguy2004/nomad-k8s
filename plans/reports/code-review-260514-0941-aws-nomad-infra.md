# AWS Nomad Infrastructure Code Review

**Date:** 2026-05-14  
**Reviewer:** code-reviewer  
**Scope:** Terraform/Terragrunt stacks, Packer AMI, Nomad jobs, Vault policies, shell scripts

---

## Summary

Well-structured HashiStack infrastructure with good DRY patterns via Terragrunt. Several **security issues require attention** before production deployment, particularly around TLS/network exposure and secrets handling.

---

## Critical Issues

### 1. Vault TLS Disabled in Production Config
**File:** `infra/shared/config/vault.hcl:8`
```hcl
tls_disable = 1
```
- Vault API exposed over HTTP exposes tokens/secrets in transit
- **Fix:** Enable TLS with certificates, or use internal TLS via Consul Connect

### 2. Management Ports Open to World (Dev Config)
**File:** `infra/environments/dev/base-infra/terragrunt.hcl:15`
```hcl
allowed_cidr = "0.0.0.0/0"
```
- Nomad (4646-4648), Vault (8200), Consul (8500-8502) accessible from any IP
- Combined with TLS disabled = credential theft risk
- **Fix:** Restrict to VPN/bastion CIDR or use SSM Session Manager

### 3. Vault Init Credentials Written to /tmp
**File:** `vault/setup/init-vault.sh:16`
```bash
vault operator init ... > /tmp/vault-init.json
```
- Root token and recovery keys persist in world-readable temp file
- **Fix:** Output to stdout only, or encrypt with AWS KMS and push to Secrets Manager immediately

### 4. RDS Secrets Manager No Recovery Window
**File:** `infra/stacks/data/rds.tf:60`
```hcl
recovery_window_in_days = 0
```
- Secret immediately deleted on resource destroy - no recovery possible
- **Fix:** Set to 7 days minimum for production

---

## High Priority

### 5. Single AZ RDS - No HA
**File:** `infra/stacks/data/rds.tf`
- No `multi_az = true` configured
- Single AZ failure = database outage
- **Recommendation:** Enable multi_az for production environments

### 6. RDS skip_final_snapshot = true
**File:** `infra/stacks/data/rds.tf:51`
- Data loss on destroy
- Acceptable for dev, but parameterize for prod

### 7. Drone Runner Privileged Container + Docker Socket
**File:** `jobs/system/drone-runner.nomad.hcl:14-17`
```hcl
privileged = true
volumes = ["/var/run/docker.sock:/var/run/docker.sock"]
```
- Container escape risk - full host access
- **Recommendation:** Use rootless Docker or isolated runner nodes

### 8. Nomad Jobs Use `latest` Image Tags
**Files:** `jobs/wordpress.nomad.hcl:20`, `jobs/laravel.nomad.hcl:25,53`
- Non-deterministic deployments
- **Fix:** Pin to digest or semantic version

---

## Medium Priority

### 9. Vault Policy Path Mismatch
**File:** `vault/policies/wordpress.hcl:5` vs `jobs/wordpress.nomad.hcl:33`
- Policy allows `secret/data/wordpress/*` (with wildcard)
- Job reads `secret/data/wordpress` (no trailing path)
- Works due to KV v2 path structure, but confusing - verify paths match intent

### 10. EC2 Public IP + Public Subnet
**File:** `infra/stacks/cluster/ec2.tf:10`
```hcl
associate_public_ip_address = true
```
- Direct internet exposure for cluster nodes
- Consider private subnet + NAT or use AWS PrivateLink for API access

### 11. IAM ec2:Describe* on Resource "*"
**File:** `infra/stacks/cluster/iam.tf:44`
- Required for Consul auto-join but overly broad
- Acceptable trade-off, but document reasoning

### 12. Shell Script Hardcoded Sleep
**File:** `infra/shared/scripts/server.sh:10`
```bash
sleep 15
```
- Fragile timing dependency for network readiness
- **Recommendation:** Use retry loop with health check instead

---

## Low Priority

### 13. Dockerfile Version Pinning
- `nomad-deploy/Dockerfile` pins Nomad 1.7.0 but Packer installs 2.0.1
- Mismatch may cause job compatibility issues

### 14. nginx-lb Memory Allocation
**File:** `jobs/system/nginx-lb.nomad.hcl:73`
- 64MB may be tight under load
- Monitor and increase if OOM-killed

### 15. Consul Key vs Vault Secret in Templates
**Files:** `jobs/wordpress.nomad.hcl:27`, `jobs/laravel.nomad.hcl:33,60`
```hcl
WORDPRESS_DB_HOST={{key "rds/endpoint"}}
```
- Mixes Consul KV (`key`) with Vault secrets in same template
- Consul key `rds/endpoint` must be manually populated - not shown in setup scripts

---

## Positive Observations

- **Terragrunt DRY patterns:** Good use of `find_in_parent_folders()` and dependencies
- **S3 security:** Public access blocked, versioning enabled, lifecycle rules configured
- **KMS key rotation:** Enabled for Vault auto-unseal
- **Nomad canary deployments:** Update stanza with auto_revert configured
- **Vault dynamic database creds:** 1h TTL with proper role separation
- **Consul Connect:** Service mesh sidecar configured for app services

---

## Recommendations

1. **Immediate (before any deployment):**
   - Enable Vault TLS or deploy behind Consul Connect
   - Restrict `allowed_cidr` to VPN/bastion range
   - Fix vault init script credential handling

2. **Before production:**
   - Enable RDS multi_az
   - Pin image versions in Nomad jobs
   - Parameterize `skip_final_snapshot` and `recovery_window_in_days`
   - Document Consul KV bootstrap for `rds/endpoint`

3. **Hardening:**
   - Move cluster to private subnet with NAT
   - Replace privileged Drone runner with isolated solution
   - Add CloudWatch alarms for cluster health

---

## Unresolved Questions

1. How is `rds/endpoint` Consul key populated? Not in any setup script reviewed.
2. Is SSM Session Manager available as alternative to direct SSH/port exposure?
3. What is the production environment override strategy for security settings?
