# Plan: Elastic IP for EC2 Stop/Start

**Goal:** Enable EC2 instances to be stopped/started without breaking services due to IP changes.

**Status:** Complete

## New Static IPs

| Node | Elastic IP | Private IP |
|------|------------|------------|
| Node 1 | 54.67.128.132 | 10.0.1.17 |
| Node 2 | 52.52.241.232 | 10.0.1.211 |
| Node 3 | 13.52.176.58 | 10.0.1.40 |

## Problem Analysis

When EC2 instances are stopped and restarted:
- AWS assigns new public IPs
- Services depending on these IPs break

### Affected Services

| Service | Location | Impact |
|---------|----------|--------|
| CloudFront Origin | `cdn/terragrunt.hcl` → `app_origin_domain` | CDN cannot reach app |
| Consul UI | Direct access via public IP | URL changes |
| Nomad UI | Direct access via public IP | URL changes |
| Vault UI | Direct access via public IP | URL changes |
| SSH Access | `~/.ssh/config` or direct IP | Connection fails |
| Vault ACM Cert SANs | Certificate may have old IP | TLS errors |

### Current Architecture
```
Internet → Public IP (dynamic) → EC2 Instances
                ↑
         Changes on stop/start
```

## Solution: Elastic IPs

### Proposed Architecture
```
Internet → Elastic IP (static) → EC2 Instances
                ↑
         Persists across stop/start
```

### Cost Analysis

| Scenario | Cost |
|----------|------|
| EIP attached to running instance | $0.00/hour |
| EIP attached to stopped instance | $0.005/hour |
| 3 EIPs × 12 hours/day stopped × 30 days | ~$5.40/month |

**Total additional cost:** ~$5-6/month for ability to stop instances

## Implementation Phases

- [x] Phase 1: Add Elastic IPs to Terraform
- [x] Phase 2: Update dependent services (outputs now use EIPs)
- [x] Phase 3: Create stop/start scripts

## Files to Modify

```
infra/stacks/cluster/
├── eip.tf           (NEW) - Elastic IP resources
├── ec2.tf           (MODIFY) - Associate EIPs
├── outputs.tf       (MODIFY) - Output EIP addresses
└── variables.tf     (MODIFY) - Add EIP toggle

infra/stacks/cdn/
└── cloudfront.tf    (REVIEW) - Origin uses output, auto-updates

scripts/
├── cluster-stop.sh  (NEW) - Stop all EC2 instances
└── cluster-start.sh (NEW) - Start all EC2 instances
```

## Success Criteria

1. EC2 instances can be stopped/started without IP changes
2. All services remain accessible after restart
3. Cost increase < $10/month
4. Scripts for easy stop/start operations
