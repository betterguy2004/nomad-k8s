variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for building the AMI"
}

variable "instance_type" {
  type        = string
  default     = "t2.medium"
  description = "Instance type for Packer builder"
}

variable "ami_name_prefix" {
  type        = string
  default     = "hashistack"
  description = "Prefix for AMI name"
}
