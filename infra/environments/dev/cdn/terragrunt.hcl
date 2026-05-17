include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../stacks/cdn"
}

dependency "base_infra" {
  config_path = "../base-infra"
}

dependency "data" {
  config_path = "../data"
}

dependency "cluster" {
  config_path = "../cluster"
}

inputs = {
  domain_name               = "hungpq.io.vn"
  route53_zone_id           = dependency.base_infra.outputs.route53_zone_id
  s3_bucket_regional_domain = dependency.data.outputs.s3_bucket_regional_domain
  cloudfront_oai_path       = dependency.data.outputs.cloudfront_oai_path
  app_origin_domain         = dependency.cluster.outputs.first_node_public_dns
}
