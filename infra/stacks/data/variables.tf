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

variable "private_subnet_id" {
  type        = string
  description = "Private subnet ID for RDS"
}

variable "rds_security_group_id" {
  type        = string
  description = "Security group ID for RDS"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}
