###############################################################################
# personal/infra/existing — the IMPORT stack.
#
# Tracks the live, pre-existing resources that were created by hand / old CFN
# and that we are KEEPING (S3 sites, CloudFront, ACM). Goal: a complete replica
# so nothing on the account is orphan/untracked. Greenfield shared-infra (new
# VPC/Postgres/budgets for NEW apps) lives in ../terraform, a separate stack.
#
# Resources are brought in via `import {}` blocks (Terraform 1.5+) with
# `terraform plan -generate-config-out=...`, then reconciled to zero-diff.
###############################################################################

terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket       = "nirlendu-tfstate-419105693501"
    key          = "existing/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # native S3 state locking (no DynamoDB)
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# Default provider — us-east-1. CloudFront is global (its API lives here) and
# CloudFront ACM certs MUST be us-east-1.
provider "aws" {
  region = "us-east-1"
}

# S3 buckets live in multiple regions — aliased providers so each bucket's
# sub-resources hit the right regional endpoint.
provider "aws" {
  alias  = "ap_south_1"
  region = "ap-south-1"
}

provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"
}
