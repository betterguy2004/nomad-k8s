# Phase 1: Add Elastic IPs to Terraform

**Status:** Pending  
**Priority:** High

## Overview

Add Elastic IP resources for each EC2 instance to maintain static public IPs across stop/start cycles.

## Implementation Steps

### 1. Create `infra/stacks/cluster/eip.tf`

```hcl
resource "aws_eip" "nomad_cluster" {
  count  = var.cluster_size
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-node-${count.index}"
  }
}

resource "aws_eip_association" "nomad_cluster" {
  count         = var.cluster_size
  instance_id   = aws_instance.nomad_cluster[count.index].id
  allocation_id = aws_eip.nomad_cluster[count.index].id
}
```

### 2. Update `infra/stacks/cluster/outputs.tf`

Replace dynamic public IPs with EIP addresses:

```hcl
output "node_public_ips" {
  value       = aws_eip.nomad_cluster[*].public_ip
  description = "Elastic IPs for cluster nodes"
}

output "first_node_public_ip" {
  value       = aws_eip.nomad_cluster[0].public_ip
  description = "First node Elastic IP (for CloudFront origin)"
}
```

### 3. Update Security Group (if needed)

Verify security group allows traffic to EIP addresses.

## Validation

- [ ] `terragrunt plan` shows 3 EIPs + 3 associations
- [ ] `terragrunt apply` completes successfully
- [ ] All services accessible via new static IPs
- [ ] Stop/start instance → IP remains same

## Rollback

```bash
# Remove EIP resources from state if needed
terragrunt state rm aws_eip.nomad_cluster
terragrunt state rm aws_eip_association.nomad_cluster
```

## Notes

- EIPs are free when attached to running instances
- Charged ~$0.005/hour when instance is stopped
- Maximum 5 EIPs per region by default (can request increase)
