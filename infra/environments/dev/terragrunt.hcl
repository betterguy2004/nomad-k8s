remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket  = "nomad-infra-tfstate-dev"
    key     = "${path_relative_to_include()}/terraform.tfstate"
    region  = "us-west-1"
    encrypt = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project
      ManagedBy   = "terragrunt"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project
      ManagedBy   = "terragrunt"
    }
  }
}
EOF
}

inputs = {
  environment = "dev"
  project     = "nomad-k8s"
  aws_region  = "us-west-1"
}
