resource "aws_s3_bucket" "media" {
  bucket = "${local.name_prefix}-media-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${local.name_prefix}-media"
  }
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket = aws_s3_bucket.media.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_cloudfront_origin_access_identity" "media" {
  comment = "OAI for ${local.name_prefix} media bucket"
}

resource "aws_s3_bucket_policy" "media" {
  bucket = aws_s3_bucket.media.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "CloudFrontOAI"
      Effect = "Allow"
      Principal = {
        AWS = aws_cloudfront_origin_access_identity.media.iam_arn
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.media.arn}/*"
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.media]
}
