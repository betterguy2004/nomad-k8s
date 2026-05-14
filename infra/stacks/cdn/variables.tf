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

variable "domain_name" {
  type        = string
  description = "Domain name for CloudFront and ACM"
}

variable "route53_zone_id" {
  type        = string
  description = "Route53 hosted zone ID"
}

variable "s3_bucket_regional_domain" {
  type        = string
  description = "S3 bucket regional domain for CloudFront origin"
}

variable "cloudfront_oai_path" {
  type        = string
  description = "CloudFront OAI path for S3 origin"
}

variable "app_origin_domain" {
  type        = string
  description = "App origin domain (EC2 public IP or LB)"
}
