# AWS Infrastructure Cost Estimation

Cost breakdown for running nomad-k8s infrastructure in **us-west-1** region.

## Hourly Cost Summary

| Resource | Qty | Unit Price | Hourly Cost |
|----------|-----|------------|-------------|
| EC2 t3.medium | 3 | $0.0416/hr | **$0.1248** |
| RDS db.t3.micro | 1 | $0.017/hr | **$0.0170** |
| RDS Storage (20GB gp3) | 1 | $0.08/GB-mo | **$0.0022** |
| KMS Key | 1 | $1.00/mo | **$0.0014** |
| Route53 Hosted Zone | 1 | $0.50/mo | **$0.0007** |
| S3 Storage | ~0 | $0.023/GB-mo | **$0.0000** |
| CloudFront | 1 | per-request | **$0.0000** |
| **TOTAL** | | | **$0.1461/hr** |

## Monthly Projection (730 hours)

| Resource | Monthly Cost |
|----------|-------------|
| EC2 (3x t3.medium) | $91.13 |
| RDS (db.t3.micro) | $12.41 |
| RDS Storage (20GB) | $1.60 |
| KMS Key | $1.00 |
| Route53 Zone | $0.50 |
| S3 (estimated 10GB) | $0.23 |
| CloudFront (10GB transfer) | $0.85 |
| Data Transfer (5GB out) | $0.45 |
| **TOTAL** | **~$108.17/mo** |

## Cost Breakdown by Service

### EC2 Instances (67% of total)
- **Instance Type**: t3.medium (2 vCPU, 4GB RAM)
- **Count**: 3 nodes (Nomad/Consul/Vault cluster)
- **Pricing**: $0.0416/hour per instance
- **Monthly**: $91.13 (on-demand)

**Cost Optimization Options**:
| Option | Savings | Monthly Cost |
|--------|---------|--------------|
| On-Demand | 0% | $91.13 |
| 1-yr Reserved (No Upfront) | ~35% | $59.23 |
| 1-yr Reserved (All Upfront) | ~40% | $54.68 |
| Spot Instances | ~60-70% | $27-36 |

### RDS MySQL (11% of total)
- **Instance**: db.t3.micro (2 vCPU, 1GB RAM)
- **Storage**: 20GB gp3
- **Backup**: 7-day retention (free up to DB size)
- **Monthly**: $14.01

### Storage & CDN (~2% of total)
- **S3**: Pay per GB stored + requests
- **CloudFront**: $0.085/GB data transfer (North America)
- Minimal cost until significant traffic

### Other Services (~1% of total)
- **KMS**: $1/month + $0.03/10K requests
- **Route53**: $0.50/zone + $0.40/million queries

## What We Avoided

| Resource NOT Used | Potential Cost |
|-------------------|----------------|
| NAT Gateway | $32.40/mo + $0.045/GB |
| Elastic IP (unused) | $3.65/mo each |
| Multi-AZ RDS | +$12.41/mo |
| Larger EC2 instances | varies |

**Savings from architecture decisions**: ~$35-50/month

## Cost by Time Period

| Period | Cost |
|--------|------|
| 1 Hour | $0.15 |
| 8 Hours (workday) | $1.17 |
| 24 Hours | $3.51 |
| 1 Week | $24.54 |
| 1 Month | $108.17 |
| 1 Year | $1,298 |

## Resource Utilization Notes

1. **EC2**: Running 24/7, consider scheduling for dev environments
2. **RDS**: Can stop when not in use (max 7 days)
3. **S3/CloudFront**: Pay-per-use, scales with traffic
4. **Secrets Manager**: $0.40/secret/month (not included above)

## Dev Environment Cost Savings Tips

1. **Stop RDS when not in use**: Save $12/mo
2. **Use Spot instances for workers**: Save 60-70% on EC2
3. **Schedule EC2 shutdown nights/weekends**: Save ~65% ($59/mo)
4. **Reserved instances for long-term**: Save 35-40%

## Pricing Sources

- EC2: https://aws.amazon.com/ec2/pricing/on-demand/
- RDS: https://aws.amazon.com/rds/mysql/pricing/
- S3: https://aws.amazon.com/s3/pricing/
- CloudFront: https://aws.amazon.com/cloudfront/pricing/
- Route53: https://aws.amazon.com/route53/pricing/
- KMS: https://aws.amazon.com/kms/pricing/

---
*Last Updated: 2026-05-14*
*Region: us-west-1 (N. California)*
*All prices in USD, subject to change*
