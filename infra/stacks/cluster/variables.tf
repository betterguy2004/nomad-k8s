variable "environment" {
  type        = string
  description = "Environment name"
}

variable "project" {
  type        = string
  description = "Project name"
}

variable "aws_region" {
  type        = string
  description = "AWS region"
}

variable "ami_id" {
  type        = string
  description = "Packer-built AMI ID"
}

variable "public_subnet_id" {
  type        = string
  description = "Public subnet ID for EC2 instances"
}

variable "cluster_security_group_id" {
  type        = string
  description = "Security group ID for cluster"
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for Vault auto-unseal"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for IAM policy"
}

variable "vault_kms_policy_arn" {
  type        = string
  description = "IAM policy ARN for Vault KMS access"
}

variable "s3_bucket_arn" {
  type        = string
  description = "S3 bucket ARN for media"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.medium"
}

variable "server_count" {
  type        = number
  description = "Number of cluster nodes"
  default     = 3
}

variable "retry_join" {
  type = map(string)
  default = {
    provider  = "aws"
    tag_key   = "ConsulAutoJoin"
    tag_value = "auto-join"
  }
  description = "Consul auto-join configuration"
}

variable "ssh_key_name" {
  type        = string
  description = "SSH key pair name"
  default     = ""
}
