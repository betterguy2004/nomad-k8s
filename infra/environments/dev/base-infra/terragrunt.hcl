include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../stacks/base-infra"
}

inputs = {
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidr  = "10.0.1.0/24"
  private_subnet_cidr = "10.0.2.0/24"
  availability_zone   = "us-west-1a"
  domain_name         = "hungpq.io.vn"
  allowed_cidr        = "0.0.0.0/0"
}
