terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket       = "nirlendu-tfstate-419105693501"
    key          = "shared/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # native S3 state locking (no DynamoDB)
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # Packages the circuit-breaker Lambda from source at plan time, so the
    # function's code is reviewable Python in the repo rather than a committed
    # zip. See 09-circuit-breaker.tf.
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "shared-infra"
      Env       = var.env
      ManagedBy = "terraform"
      Scope     = "account-wide"
    }
  }
}

# CE / Budgets / CloudWatch billing all live in us-east-1.
provider "aws" {
  alias  = "billing"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "shared-infra"
      Env       = var.env
      ManagedBy = "terraform"
      Scope     = "account-wide"
    }
  }
}
