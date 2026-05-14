output "vpc_id" {
  value       = aws_vpc.main.id
  description = "VPC ID"
}

output "vpc_cidr" {
  value       = aws_vpc.main.cidr_block
  description = "VPC CIDR block"
}

output "public_subnet_id" {
  value       = aws_subnet.public.id
  description = "Public subnet ID"
}

output "private_subnet_id" {
  value       = aws_subnet.private.id
  description = "Private subnet ID"
}

output "cluster_security_group_id" {
  value       = aws_security_group.nomad_cluster.id
  description = "Nomad cluster security group ID"
}

output "rds_security_group_id" {
  value       = aws_security_group.rds.id
  description = "RDS security group ID"
}

output "kms_key_id" {
  value       = aws_kms_key.vault_unseal.key_id
  description = "KMS key ID for Vault auto-unseal"
}

output "kms_key_arn" {
  value       = aws_kms_key.vault_unseal.arn
  description = "KMS key ARN for Vault auto-unseal"
}

output "vault_kms_policy_arn" {
  value       = aws_iam_policy.vault_kms.arn
  description = "IAM policy ARN for Vault KMS access"
}

output "route53_zone_id" {
  value       = aws_route53_zone.main.zone_id
  description = "Route53 hosted zone ID"
}

output "route53_nameservers" {
  value       = aws_route53_zone.main.name_servers
  description = "Route53 nameservers for domain delegation"
}
