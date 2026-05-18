output "node_ids" {
  value       = aws_instance.nomad_cluster[*].id
  description = "EC2 instance IDs"
}

output "node_public_ips" {
  value       = aws_eip.nomad_cluster[*].public_ip
  description = "Elastic IPs for cluster nodes (static)"
}

output "node_public_dns" {
  value       = aws_eip.nomad_cluster[*].public_dns
  description = "Public DNS names for cluster Elastic IPs"
}

output "node_private_ips" {
  value       = aws_instance.nomad_cluster[*].private_ip
  description = "Private IPs for internal routing"
}

output "first_node_public_ip" {
  value       = aws_eip.nomad_cluster[0].public_ip
  description = "First node Elastic IP"
}

output "first_node_public_dns" {
  value       = aws_eip.nomad_cluster[0].public_dns
  description = "First node public DNS name for CloudFront origin"
}

output "consul_ui_url" {
  value       = "http://${aws_eip.nomad_cluster[0].public_ip}:8500"
  description = "Consul UI URL"
}

output "vault_ui_url" {
  value       = "https://${aws_eip.nomad_cluster[0].public_ip}:8200"
  description = "Vault UI URL"
}

output "nomad_ui_url" {
  value       = "http://${aws_eip.nomad_cluster[0].public_ip}:4646"
  description = "Nomad UI URL"
}

output "iam_role_arn" {
  value       = aws_iam_role.nomad_cluster.arn
  description = "IAM role ARN for cluster instances"
}

output "eip_allocation_ids" {
  value       = aws_eip.nomad_cluster[*].id
  description = "EIP allocation IDs"
}

output "data_volume_ids" {
  value       = aws_ebs_volume.data[*].id
  description = "Persistent data EBS volume IDs"
}

output "data_volume_attachments" {
  value       = aws_volume_attachment.data[*].device_name
  description = "Device names for data volume attachments"
}
