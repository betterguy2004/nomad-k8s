output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.main.id
  description = "CloudFront distribution ID"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.main.domain_name
  description = "CloudFront domain name"
}

output "cloudfront_hosted_zone_id" {
  value       = aws_cloudfront_distribution.main.hosted_zone_id
  description = "CloudFront hosted zone ID"
}

output "acm_certificate_arn" {
  value       = aws_acm_certificate.main.arn
  description = "ACM certificate ARN"
}

output "domain_url" {
  value       = "https://${var.domain_name}"
  description = "Primary domain URL"
}
