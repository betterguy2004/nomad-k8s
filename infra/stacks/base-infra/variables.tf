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
  description = "CIDR block for private subnet (AZ1)"
  default     = "10.0.2.0/24"
}

variable "private_subnet_cidr_2" {
  type        = string
  description = "CIDR block for private subnet (AZ2)"
  default     = "10.0.3.0/24"
}

variable "availability_zone" {
  type        = string
  description = "Primary availability zone"
}

variable "availability_zone_2" {
  type        = string
  description = "Secondary availability zone (for RDS multi-AZ)"
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
