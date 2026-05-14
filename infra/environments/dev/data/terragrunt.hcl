include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../stacks/data"
}

dependency "base_infra" {
  config_path = "../base-infra"
}

inputs = {
  vpc_id                = dependency.base_infra.outputs.vpc_id
  private_subnet_id     = dependency.base_infra.outputs.private_subnet_id
  rds_security_group_id = dependency.base_infra.outputs.rds_security_group_id
}
