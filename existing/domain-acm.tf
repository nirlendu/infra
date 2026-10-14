###############################################################################
# ONE DNS-validated certificate per held domain — apex AND wildcard on the same
# certificate, every time.
#
# This is the shape supertravelr-acm.tf established, generalised to a list so a
# new domain is one line rather than one file. Each certificate carries exactly
# two names, `<domain>` and `*.<domain>`, so any single-label host under it (www,
# api, app, assets…) is covered without issuing another.
#
# ── Why DNS, always ──────────────────────────────────────────────────────────
# superwomn.com is the reason this file exists. Its EMAIL-validated certificate
# lapsed on 2026-10-04: an email renewal needs a human to click a link within 72
# hours, every renewal, forever, and nobody did. A DNS-validated certificate
# renews itself for as long as its validation CNAME stays put, and that CNAME is
# in code — `acm_validation` in ../cloudflare/dns-records.tf.
#
# ── Two-phase, like every DNS-validated certificate here ─────────────────────
# ACM issues only once the validation record resolves, and that record lives in
# Cloudflare, which a different stack manages under a role that cannot read this
# stack's state. So:
#
#   1. add the domain below, apply with
#        -var 'domain_certs_pending=["<domain>"]'
#   2. copy `terraform output domain_acm_validation_records` into
#      ../cloudflare/dns-records.tf and apply that stack
#   3. apply this one with no -var
#
# Pending is per DOMAIN, not one switch for the file: a single bool would
# destroy every other domain's validation resource while a new one waits, and
# the distributions that reference those would lose their certificate.
#
# ── Who consumes these ───────────────────────────────────────────────────────
# In this stack, through the VALIDATION resource so nothing can be pointed at a
# certificate still in PENDING_VALIDATION: superwomn, suprhealthe, nirlendu and
# geniusjnr's distributions in generated_cloudfront.tf.
#
# agitome.com is consumed by agitome-app-v1's own stack — four distributions and
# the API Gateway domain — through a `data "aws_acm_certificate"` lookup by
# domain with most_recent = true, so it follows whichever ISSUED certificate is
# newest and needs no ARN copied across.
#
# The rest are held domains with nothing served yet; each certificate is ready
# for whichever stack serves that domain first.
###############################################################################

locals {
  # Every Cloudflare zone this account holds whose certificate is not declared
  # somewhere else. Covered elsewhere, and so NOT here: supertravelr.com
  # (supertravelr-acm.tf), mastersbound.com (its web stack), maxinterview.com
  # (generated_acm.tf, re-issued under DNS) and authoxi.com (DNS-validated,
  # outside Terraform).
  dns_validated_domains = toset([
    "aeternm.com",
    "agentlox.com",
    "agentparle.com",
    "agicite.com",
    "agiremit.com",
    "agitome.com",
    "allowline.com",
    "betterity.com",
    "fetchtoll.com",
    "geniusjnr.com",
    "longahealth.com",
    "maxagenter.com",
    "nirlendu.com",
    "purvadas.com",
    "rashtrnirman.com",
    "superwomn.com",
    "suprhealthe.com",
  ])
}

resource "aws_acm_certificate" "domain" {
  for_each = local.dns_validated_domains

  domain_name               = each.key
  subject_alternative_names = ["*.${each.key}"]
  validation_method         = "DNS"

  # Renewals and any future replacement issue the new certificate before the
  # old one is released, so a consumer never sees a gap.
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name      = each.key
    ManagedBy = "terraform"
  }
}

resource "aws_acm_certificate_validation" "domain" {
  for_each = setsubtract(local.dns_validated_domains, var.domain_certs_pending)

  certificate_arn = aws_acm_certificate.domain[each.key].arn
  validation_record_fqdns = distinct([
    for o in aws_acm_certificate.domain[each.key].domain_validation_options :
    o.resource_record_name
  ])
}

variable "domain_certs_pending" {
  description = <<-EOT
    Domains whose validation record is not in Cloudflare yet — set only between
    phase 1 and phase 3 above, and only to the domains being added. Leave it empty
    otherwise: listing a domain that is already served drops its validation
    resource, and the distributions that reference it lose their certificate.
  EOT
  type        = set(string)
  default     = []
}

output "domain_acm_validation_records" {
  description = "One CNAME per domain — the apex and the wildcard share it. Copy into acm_validation in ../cloudflare/dns-records.tf (DNS-only)."
  value = {
    for d, c in aws_acm_certificate.domain : d => one(distinct([
      for o in c.domain_validation_options : {
        name  = trimsuffix(o.resource_record_name, ".")
        type  = o.resource_record_type
        value = trimsuffix(o.resource_record_value, ".")
      }
    ]))
  }
}
