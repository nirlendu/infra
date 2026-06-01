# Minimal config to `terraform validate` the module. Not meant to be applied.
# Uses this directory's own user-data stub so templatefile() has a real file.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.60" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  default_tags {
    tags = { Project = "example", Env = "prod", ManagedBy = "terraform" }
  }
}

module "app" {
  source = "../../"

  name_prefix     = "example"
  alert_email     = "you@example.com"
  git_repo_url    = "https://github.com/example/example.git"
  instance_type   = "t4g.small"
  user_data_path  = abspath("${path.module}/user-data.stub.sh")
  app_secret_keys = ["EXAMPLE_API_KEY"]
}
