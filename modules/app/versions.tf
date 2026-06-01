terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
}

# NOTE: this is a reusable module — it declares NO provider block. The consuming
# root (each app's infra/terraform/) configures the aws provider, including the
# default_tags { Project = <name_prefix> } that the per-app budget filter relies on.
