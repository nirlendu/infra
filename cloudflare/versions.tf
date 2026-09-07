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
# AUTH: CLOUDFLARE_API_TOKEN, loaded from SSM rather than kept in a dotfile:
#
#   eval "$(make token)"
#
# The token lives at /shared/prod/cloudflare/api-token, declared in
# ../terraform/06-cloudflare-token.tf. Terraform owns the parameter; the VALUE is
# set out of band and never enters Terraform state — `terraform plan` refreshes,
# and refreshing an aws_ssm_parameter reads the value back, so a token managed
# the ordinary way would be readable by anything that can plan this stack.
#
# `make token` reads it as the `cloudflare-edge` role, which can reach that one
# parameter and the `cloudflare/*` tfstate prefix and nothing else in the
# account. Not AdministratorAccess, which is what this stack was applied as
# before, and not `agent`, which is scoped to authoxi.
#
#   Scope the token itself to: Zone:Read, Zone Settings:Edit, Cache Rules:Edit,
#   Zone WAF:Edit, Bot Management:Edit, DNS:Edit, Cache Purge (for `make purge`)
#
#   Zone WAF is what the Rulesets API needs for rate limiting — "Firewall
#   Services" is a DIFFERENT permission and is NOT enough. Symptom: 403 on
#   rulesets/phases/http_ratelimit/entrypoint while firewall/rules returns 200.
#
#   DNS:Edit was added 2026-09-07 for the mastersbound.com cutover. Until then
#   the token could not read a single DNS record, so no record in this account
#   was in Terraform and none could be — which is why the zone was still carrying
#   GoDaddy's parking records months after the domain was pointed here. DNS
#   records are NOT owned by this stack; see the note below.
#
#   WHERE DNS RECORDS LIVE. The estate's rule, settled 2026-09-07:
#
#     A product stack owns the records that point at resources IT creates.
#     This stack owns zone-level records (mail, domain verification) and how
#     the edge behaves.
#
#   So `mastersbound.com -> the uni-web distribution`, its `www`, and that
#   certificate's ACM validation records are all in
#   mastersbound/mastersbound-web-v2/infra/terraform/dns.tf — the only stack that
#   knows the distribution's domain name. This stack keeps its narrow
#   `cloudflare-edge` role, which has no ACM rights and needs none.
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
