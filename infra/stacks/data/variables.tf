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

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for RDS (requires 2 AZs)"
}

variable "rds_security_group_id" {
  type        = string
  description = "Security group ID for RDS"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}
