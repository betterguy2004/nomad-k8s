resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  default_root_object = "index.html"
  aliases             = [var.domain_name, "*.${var.domain_name}"]
  price_class         = "PriceClass_100"
  comment             = "${local.name_prefix} distribution"

  origin {
    domain_name = var.s3_bucket_regional_domain
    origin_id   = "S3Media"

    s3_origin_config {
      origin_access_identity = var.cloudfront_oai_path
    }
  }

  origin {
    domain_name = var.app_origin_domain
    origin_id   = "AppOrigin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  ordered_cache_behavior {
    path_pattern     = "/media/*"
    target_origin_id = "S3Media"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    compress         = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
  }

  default_cache_behavior {
    target_origin_id = "AppOrigin"
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    compress         = true

    forwarded_values {
      query_string = true
      headers      = ["Host", "Authorization", "Origin"]
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.main.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "${local.name_prefix}-cdn"
  }
}

resource "aws_route53_record" "main" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wildcard" {
  zone_id = var.route53_zone_id
  name    = "*.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}
