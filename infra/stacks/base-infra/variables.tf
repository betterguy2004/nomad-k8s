variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
}

variable "project" {
  type        = string
  description = "Project name for resource tagging"
}

variable "aws_region" {
  type        = string
  description = "AWS region for resources"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR block for public subnet"
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type        = string
  description = "CIDR block for private subnet"
  default     = "10.0.2.0/24"
}

variable "availability_zone" {
  type        = string
  description = "Availability zone for subnets"
}

variable "domain_name" {
  type        = string
  description = "Domain name for Route53 hosted zone"
}

variable "allowed_cidr" {
  type        = string
  description = "CIDR for SSH/admin access (your IP)"
  default     = "0.0.0.0/0"
}
