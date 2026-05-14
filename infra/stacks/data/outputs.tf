output "rds_endpoint" {
  value       = aws_db_instance.mysql.endpoint
  description = "RDS MySQL endpoint"
}

output "rds_address" {
  value       = aws_db_instance.mysql.address
  description = "RDS MySQL address (hostname only)"
}

output "rds_port" {
  value       = aws_db_instance.mysql.port
  description = "RDS MySQL port"
}

output "rds_database_name" {
  value       = aws_db_instance.mysql.db_name
  description = "RDS database name"
}

output "rds_secret_arn" {
  value       = aws_secretsmanager_secret.rds_master.arn
  description = "Secrets Manager ARN for RDS master credentials"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.media.id
  description = "S3 media bucket name"
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.media.arn
  description = "S3 media bucket ARN"
}

output "s3_bucket_regional_domain" {
  value       = aws_s3_bucket.media.bucket_regional_domain_name
  description = "S3 bucket regional domain for CloudFront origin"
}

output "cloudfront_oai_id" {
  value       = aws_cloudfront_origin_access_identity.media.id
  description = "CloudFront OAI ID"
}

output "cloudfront_oai_path" {
  value       = aws_cloudfront_origin_access_identity.media.cloudfront_access_identity_path
  description = "CloudFront OAI path for S3 origin"
}
