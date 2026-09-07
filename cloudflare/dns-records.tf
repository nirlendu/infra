###############################################################################
# DNS records.
#
# ── Why this file did not exist until 2026-09-07 ──────────────────────────────
# This stack managed zone settings, cache rules, WAF and bot policy — everything
# ABOUT a zone except the records in it. So every hostname in the account was
# created by hand in the dashboard, which put DNS outside the one rule this
# workspace is strictest about: infrastructure changes go through Terraform,
# and that rule names Cloudflare explicitly.
#
# It surfaced when visa-api.supertravelr.com needed two records and there was
# nowhere in code to put them. The token already carries DNS:Edit, so the gap was
# never a permissions problem — just an unwritten file.
#
# ── Scope: NEW records only, deliberately ────────────────────────────────────
# The fourteen records already in the supertravelr zone (MX, five verification
# TXTs, the apex, www, trips, web, visa) are NOT imported here. Importing live
# mail routing and apex traffic is a separate, riskier change that deserves its
# own plan read carefully — sweeping it in alongside a new API hostname is how a
# zone's MX record gets dropped by a stray plan. They stay hand-managed until
# somebody imports them on purpose.
#
# ── Nothing here is proxied ──────────────────────────────────────────────────
# Both records below are DNS-only (grey cloud). For the ACM validation record
# that is mandatory: a proxied CNAME returns Cloudflare's own address and ACM
# never sees the value it is looking for, so the certificate sits in
# PENDING_VALIDATION forever with a record that looks correct in the dashboard.
# For the API hostname it is a deliberate choice — see the comment there.
###############################################################################

locals {
  supertravelr_zone_id = local.active_zones.supertravelr.zone_id
}

# ── visa-api.supertravelr.com: ACM domain validation ─────────────────────────
#
# Copied from `terraform output acm_validation_record` in
# supertravelr/visa-backend-v1/infra/terraform. Deliberately copied rather than
# read through `terraform_remote_state`: this stack runs as the `cloudflare-edge`
# role, which can reach the cloudflare/* state prefix and nothing else in the
# account. That scoping is a feature, so the coupling is a copied constant with
# its provenance written down instead of a widened IAM role.
#
# The value is stable for the life of the certificate — ACM keeps the same
# validation record across automatic renewals — so this does not rot. If the
# certificate is ever destroyed and recreated, re-read that output.
resource "cloudflare_dns_record" "visa_api_acm_validation" {
  zone_id = local.supertravelr_zone_id
  name    = "_a7bafecc8598ecd6cd0bf8a2049b0c2b.visa-api.supertravelr.com"
  type    = "CNAME"
  # No trailing dot. ACM's output gives the value in absolute FQDN form
  # ("...acm-validations.aws."), but Cloudflare normalises the dot away on write,
  # so keeping it here means every future plan reports a phantom one-character
  # change to a record nobody touched — the kind of permanent diff that teaches
  # people to skim plans.
  content = "_d775b478b39a5b802128739705d10ffc.jkddzztszm.acm-validations.aws"
  ttl     = 60
  proxied = false
  comment = "ACM DNS validation for visa-api. Managed by _core/infra/cloudflare."
}

# ── visa-api.supertravelr.com -> API Gateway ─────────────────────────────────
#
# Created only once the API Gateway custom domain exists, because its target
# hostname is an output of that resource. Two-phase by necessity:
#
#   1. apply this stack with the validation record above  -> ACM issues
#   2. apply visa-backend-v1 with enable_custom_domain=true
#   3. set visa_api_target_domain below from its `cloudflare_cname` output,
#      and apply this stack again
#
# DNS-ONLY, and that is a real decision rather than an oversight. Proxying this
# hostname would put Cloudflare's cache and TLS termination in front of an
# authenticated JSON API that already sits behind API Gateway — a second TLS hop
# and a second cache for responses that must never be shared between callers.
# The zone's own /api bypass rule in cache-rules.tf exists to prevent exactly
# that for mastersbound; this avoids needing the equivalent here.
variable "visa_api_target_domain" {
  description = "API Gateway's regional target hostname for visa-api.supertravelr.com, from `terraform output cloudflare_cname` in visa-backend-v1. Set 2026-09-08 once that stack was applied with enable_custom_domain = true; empty in a fresh environment until phase 2 completes."
  type        = string
  default     = "d-hq9v04ljrk.execute-api.us-east-1.amazonaws.com"
}

resource "cloudflare_dns_record" "visa_api" {
  count = var.visa_api_target_domain == "" ? 0 : 1

  zone_id = local.supertravelr_zone_id
  name    = "visa-api.supertravelr.com"
  type    = "CNAME"
  content = var.visa_api_target_domain
  ttl     = 300
  proxied = false
  comment = "supertravelr-visa API -> API Gateway. DNS-only on purpose. Managed by _core/infra/cloudflare."
}
