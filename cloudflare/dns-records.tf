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
# Every record below is DNS-only (grey cloud). For the two ACM validation records
# that is mandatory: a proxied CNAME returns Cloudflare's own address, so ACM
# never sees the value it is looking for and the certificate sits in
# PENDING_VALIDATION forever behind a record that looks correct in the dashboard.
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

# ── supertravelr.com: ACM domain validation for the ONE domain certificate ───
#
# From `terraform output supertravelr_acm_validation_record` in ../existing.
#
# One record, not two. The certificate carries `supertravelr.com` and
# `*.supertravelr.com` as separate SANs, but ACM validates both against the same
# registrable domain and therefore emits a single CNAME — the output lists it
# twice, identically, once per SAN.
#
# This record is what replaces a human clicking a link in an inbox. The
# certificate it validates is the one behind supertravelr.com, www, trips and
# supertravelr.com/visa. Its EMAIL-validated predecessor expires 2026-10-22 with
# its renewal sitting at PENDING_VALIDATION, which would have taken all of them
# down at once. Deleting this record re-creates that failure mode — silently, at
# the next renewal rather than immediately.
resource "cloudflare_dns_record" "supertravelr_acm_validation" {
  zone_id = local.supertravelr_zone_id
  name    = "_7a12fa90e510378b2344c55a1ee00916.supertravelr.com"
  type    = "CNAME"
  # No trailing dot — Cloudflare normalises it away, and keeping it means a
  # permanent one-character diff on every plan.
  content = "_a7cc7df2087e5fb7ad95c02a595cffc4.jkddzztszm.acm-validations.aws"
  ttl     = 60
  proxied = false
  comment = "ACM DNS validation for supertravelr.com + *.supertravelr.com. Managed by _core/infra/cloudflare."
}

# ── ACM domain validation: one record per held domain ────────────────────────
#
# From `terraform output domain_acm_validation_records` in ../existing
# (domain-acm.tf), copied 2026-10-14 — copied rather than read through
# terraform_remote_state for the same reason as the visa-api record above: this
# stack's role reaches the cloudflare/* state prefix and nothing else.
#
# ONE record per domain covers BOTH names on its certificate. Each certificate
# carries `<domain>` and `*.<domain>`, and ACM validates both against the same
# registrable domain, so it emits a single CNAME for the pair.
#
# The values are stable for the life of each certificate — renewals reuse them —
# so these do not rot. Deleting one does not break anything today; it breaks that
# domain's next automatic renewal, silently, about eleven months from now. That is
# exactly how superwomn.com's email-validated certificate lapsed on 2026-10-04.
#
# Zone ids are inline for the eleven held domains because zones.tf deliberately
# lists only zones this stack applies edge policy to; a validation record is not
# edge policy, and adding them there would sweep them into cache and bot rules.
locals {
  acm_validation = {
    "aeternm.com"      = { zone_id = "82b0dd20de40b11684f34be58fe4e740", name = "_5a37ee5dec919d0ff6ccca6f9aaaf27b.aeternm.com", content = "_59594753f620f3ae59df1189b0f31eb4.wzccmgtwzk.acm-validations.aws" }
    "agentlox.com"     = { zone_id = "d73ebffdf0b40385e8a12d4f7e7940fe", name = "_8df9edce82f4900f5b43f11649abb759.agentlox.com", content = "_a4334af824114213297de31e05690dd5.wzccmgtwzk.acm-validations.aws" }
    "agentparle.com"   = { zone_id = "509d2feb0dfdd0e2942dc3bd0883b0cf", name = "_8bed55dfc30300f56efbc9add3236544.agentparle.com", content = "_66e41d0bd4bab675c3af834c9bd6e686.wzccmgtwzk.acm-validations.aws" }
    "agicite.com"      = { zone_id = "4c891a22ccc4cd9df55dd976f562d159", name = "_9a0ec2baea7cdff11b83af649a8e1c68.agicite.com", content = "_c2bc445c9cc0295f4b0a32e229092550.wzccmgtwzk.acm-validations.aws" }
    "agiremit.com"     = { zone_id = "05eebae5661a13224b4f2aa9bfc03659", name = "_a4822520dfb565c1df73190485aaa52b.agiremit.com", content = "_d5c75e2291b933ab8e4cd7592a05242d.wzccmgtwzk.acm-validations.aws" }
    "allowline.com"    = { zone_id = "a8b99440bfffd10e325406116aedfb9f", name = "_bd0e591e835d2eb614141097f5079c04.allowline.com", content = "_461920fdf12185ff63ffd36ad9530e42.wzccmgtwzk.acm-validations.aws" }
    "betterity.com"    = { zone_id = "34ac30591e8963893ba6866a72e6759b", name = "_85ff53831404d3bcbeb17ccb192d6409.betterity.com", content = "_58f171d6e25f3fbc8e5c61f08e1146e1.wzccmgtwzk.acm-validations.aws" }
    "fetchtoll.com"    = { zone_id = "d67aba49585639da0a1d74ceb1d430d9", name = "_43dba11b43ec11edf998a1a06167f74c.fetchtoll.com", content = "_9dbc770804b11ffd7a78908fcd739b59.wzccmgtwzk.acm-validations.aws" }
    "longahealth.com"  = { zone_id = "6da55e1c24b000ba73d961338764c858", name = "_b3c9fc5a65e963abb3d834fa8502b53b.longahealth.com", content = "_ffe5ead23b5f4d1bcc753bcc6fea9dc0.wzccmgtwzk.acm-validations.aws" }
    "maxagenter.com"   = { zone_id = "6ddd2ec6334c1f661d6a9a294de674bb", name = "_aad3c683bd51159aaa1537c336a3a683.maxagenter.com", content = "_2bfd082b893c3b90d290b56556a31aae.wzccmgtwzk.acm-validations.aws" }
    "rashtrnirman.com" = { zone_id = "da1db0ccf2e4edf729f7f772ccabde37", name = "_03a79f6172fb88401f16f7a20440f1be.rashtrnirman.com", content = "_25f9530b17001e2a4d889b5dc709d913.wzccmgtwzk.acm-validations.aws" }
    "superwomn.com"    = { zone_id = local.archived_zones.superwomn.zone_id, name = "_bcdac94b443250d429029f03bd12f258.superwomn.com", content = "_9bb382e8042f7a5228539b8efb36cab0.wzccmgtwzk.acm-validations.aws" }

    # The five that were EMAIL-validated until these replaced them.
    "agitome.com"     = { zone_id = local.topology_only_zones.agitome.zone_id, name = "_92d04016c289081595a90839c9aed7c7.agitome.com", content = "_c0362068c6221e38100bf524c2d7289a.wzccmgtwzk.acm-validations.aws" }
    "geniusjnr.com"   = { zone_id = local.active_zones.geniusjnr.zone_id, name = "_97ed8b511c4ebaea4ebc3f6e20bacd92.geniusjnr.com", content = "_46135fe7cf0fc2f461851ddba33ec622.wzccmgtwzk.acm-validations.aws" }
    "nirlendu.com"    = { zone_id = local.archived_zones.nirlendu.zone_id, name = "_ee5d0d1b300e1f13d2696ff501e1ce28.nirlendu.com", content = "_3db503139c832cb7e89cdbf2e0b41a94.zzxlnyslwt.acm-validations.aws" }
    "purvadas.com"    = { zone_id = "f130dcc658f20e6e0915b456b610eba9", name = "_b10c1bfdb033a26cbe404e5842a1d480.purvadas.com", content = "_e861f999191d21e20222ffd839711ef0.wzccmgtwzk.acm-validations.aws" }
    "suprhealthe.com" = { zone_id = local.archived_zones.suprhealthe.zone_id, name = "_a557d289fb398f88c423d3450ad20989.suprhealthe.com", content = "_ae9c237d5173d61ea05c43076c1058c7.wzccmgtwzk.acm-validations.aws" }
  }
}

resource "cloudflare_dns_record" "acm_validation" {
  for_each = local.acm_validation

  zone_id = each.value.zone_id
  name    = each.value.name
  type    = "CNAME"
  # No trailing dot — Cloudflare normalises it away (see above).
  content = each.value.content
  ttl     = 60
  # Mandatory: a proxied CNAME answers with Cloudflare's address, and ACM never
  # sees the value it is waiting for.
  proxied = false
  comment = "ACM DNS validation for ${each.key} + *.${each.key}. Managed by _core/infra/cloudflare."
}
