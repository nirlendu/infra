###############################################################################
# personal/infra/clusters — the COMPANY compute layer.
#
# One ECS cluster per company, shared by that company's products. This stack owns
# the objects that outlive any single product and publishes them to SSM; product
# stacks discover them and own only their own service.
#
# Why this is a stack of its own rather than a file in ../terraform or a resource
# in the first product that needed it:
#
#   * NOT in the product. The first version of uni-backend's stack created the
#     geniusjnr cluster itself. That works exactly until a second geniusjnr backend
#     exists, at which point `terraform destroy` in the FIRST product takes down the
#     cluster, the namespace and the log group — and with them every sibling
#     service. A product's state must never be able to do that.
#
#   * NOT in ../terraform. That stack owns the VPC and the production database, so
#     every apply there is a high-stakes operation. "Add a cluster for a new
#     company" is routine and should not require planning against RDS.
#
# A cluster is a free control-plane object (unlike EKS, which bills $73/mo just to
# exist), so the number of clusters here is a governance decision, not a cost one.
# The boundary is the company because that is the boundary deploys, IAM and cost
# allocation already follow.
#
# Sibling stacks:
#   ../terraform  — greenfield shared-infra (VPC, RDS, budgets, SNS, SSM)
#   ../existing   — the imported live-AWS replica (S3, CloudFront, ACM)
#   ../cloudflare — the edge
#
# Consumers: aeternm/authoxi/infra, geniusjnr/uni-backend/infra, and whatever comes
# next. See "What's published" in README.md for the parameter paths.
###############################################################################

terraform {
  required_version = ">= 1.9"

  backend "s3" {
    bucket       = "nirlendu-tfstate-419105693501"
    key          = "clusters/terraform.tfstate"
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

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Stack     = "clusters"
      Scope     = "company-shared"
    }
  }
}
