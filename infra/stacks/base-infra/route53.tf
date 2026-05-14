resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Name = "${local.name_prefix}-zone"
  }
}
