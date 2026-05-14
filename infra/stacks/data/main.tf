locals {
  name_prefix = "${var.project}-${var.environment}"
}

data "aws_caller_identity" "current" {}

resource "random_password" "rds_master" {
  length  = 24
  special = false
}
