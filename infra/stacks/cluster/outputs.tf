output "node_ids" {
  value       = aws_instance.nomad_cluster[*].id
  description = "EC2 instance IDs"
}

output "node_public_ips" {
  value       = aws_instance.nomad_cluster[*].public_ip
  description = "Public IPs for SSH/admin access"
}

output "node_private_ips" {
  value       = aws_instance.nomad_cluster[*].private_ip
  description = "Private IPs for internal routing"
}

output "first_node_public_ip" {
  value       = aws_instance.nomad_cluster[0].public_ip
  description = "First node public IP (for CloudFront origin)"
}

output "consul_ui_url" {
  value       = "http://${aws_instance.nomad_cluster[0].public_ip}:8500"
  description = "Consul UI URL"
}

output "vault_ui_url" {
  value       = "http://${aws_instance.nomad_cluster[0].public_ip}:8200"
  description = "Vault UI URL"
}

output "nomad_ui_url" {
  value       = "http://${aws_instance.nomad_cluster[0].public_ip}:4646"
  description = "Nomad UI URL"
}

output "iam_role_arn" {
  value       = aws_iam_role.nomad_cluster.arn
  description = "IAM role ARN for cluster instances"
}
