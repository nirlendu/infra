###############################################################################
# personal/infra/cloudflare — the EDGE stack.
#
# Cloudflare sits in front of every domain in this account. That is not
# cosmetic: because every hostname is proxied (orange-cloud), Cloudflare is the
# real user-facing edge and CloudFront is only an ORIGIN. Whatever Cloudflare
# serves from its own cache never reaches AWS and never bills.
#
# This stack exists because that fact was load-bearing and undocumented. In
# Aug 2026 Cloudflare took 229,945,671 requests / 7,904 GB for the
# maxinterview.com zone and absorbed 64.5% of it for free — while the ~35%
# that leaked through (uncached HTML) cost $152 at CloudFront. The edge config
# was doing most of the work and none of it was in code, so nobody could see
# the gap or reason about it.
#
# Sibling stacks:
#   ../terraform  — greenfield shared-infra (VPC, RDS, budgets, SNS, SSM)
#   ../existing   — the imported live-AWS replica (S3, CloudFront, ACM)
#
# AUTH: export CLOUDFLARE_API_TOKEN. Scope the token to:
#   Zone:Read, Zone Settings:Edit, Cache Rules:Edit, Zone WAF:Edit,
#   Bot Management:Edit, Cache Purge (for `make purge`)
#
#   Zone WAF is what the Rulesets API needs for rate limiting — "Firewall
#   Services" is a DIFFERENT permission and is NOT enough. Symptom: 403 on
#   rulesets/phases/http_ratelimit/entrypoint while firewall/rules returns 200.
###############################################################################

terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket       = "nirlendu-tfstate-419105693501"
    key          = "cloudflare/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # native S3 state locking (no DynamoDB)
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

# Token comes from CLOUDFLARE_API_TOKEN in the environment — never committed,
# never in tfvars. Cloudflare tokens are account-wide bearer credentials; a
# leaked one can repoint DNS for every domain here.
provider "cloudflare" {}
