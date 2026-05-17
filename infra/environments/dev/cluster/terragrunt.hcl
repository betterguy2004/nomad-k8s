include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../stacks/cluster"
}

dependency "base_infra" {
  config_path = "../base-infra"
}

dependency "data" {
  config_path = "../data"
}

inputs = {
  ami_id                    = "ami-03381bae674bb63b5"
  public_subnet_id          = dependency.base_infra.outputs.public_subnet_id
  cluster_security_group_id = dependency.base_infra.outputs.cluster_security_group_id
  kms_key_id                = dependency.base_infra.outputs.kms_key_id
  kms_key_arn               = dependency.base_infra.outputs.kms_key_arn
  vault_kms_policy_arn      = dependency.base_infra.outputs.vault_kms_policy_arn
  s3_bucket_arn             = dependency.data.outputs.s3_bucket_arn
  ssh_key_name              = "nomad-k8s-dev"
}
