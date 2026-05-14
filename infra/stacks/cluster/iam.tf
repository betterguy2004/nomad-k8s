resource "aws_iam_role" "nomad_cluster" {
  name = "${local.name_prefix}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${local.name_prefix}-cluster-role"
  }
}

resource "aws_iam_role_policy" "nomad_cluster" {
  name = "${local.name_prefix}-cluster-policy"
  role = aws_iam_role.nomad_cluster.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VaultKMSUnseal"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.kms_key_arn
      },
      {
        Sid    = "ConsulAutoJoin"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3MediaAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "nomad_cluster" {
  name = "${local.name_prefix}-cluster-profile"
  role = aws_iam_role.nomad_cluster.name

  tags = {
    Name = "${local.name_prefix}-cluster-profile"
  }
}
