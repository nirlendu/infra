###############################################################################
# supertravelr.com — ONE certificate for the domain, DNS-validated.
#
# ── Why a new resource instead of editing the imported one ───────────────────
# `generated_acm.tf` holds `c_supertravelr_com`, an EMAIL-validated certificate.
# `validation_method` is immutable in ACM: changing it in place forces Terraform
# to REPLACE, and replace means destroy-then-create against a certificate that is
# attached to three live distributions. ACM refuses to delete a certificate in
# use, so that apply cannot succeed — it can only fail partway. Exactly the shape
# of the c_maxinterview_com hazard fixed in this stack on 2026-09-07.
#
# So the new certificate is issued ALONGSIDE the old one. Consumers move over
# once it is ISSUED, and the old one is deleted only after nothing references it.
# At no point is a live distribution pointed at a certificate that is not yet
# valid, and every step is reversible.
#
# ── Why DNS validation is the point, not a detail ────────────────────────────
# The EMAIL certificate expires 2026-10-22 and its renewal sat at
# PENDING_VALIDATION: ACM mails five addresses at supertravelr.com and a human
# must click within 72 hours, per renewal, forever. Nobody had. Had it lapsed, the
# legacy site, trips.supertravelr.com AND supertravelr.com/visa would have failed
# TLS together, because all three ride this one certificate.
#
# A DNS-validated certificate renews itself indefinitely as long as the CNAME
# stays put — and that CNAME is now in code, in
# ../cloudflare/dns-records.tf, rather than in somebody's inbox.
#
# ── One certificate per domain ───────────────────────────────────────────────
# The apex and the wildcard are SANs on a single certificate, and the visa API
# reads this same certificate rather than issuing its own. `*.supertravelr.com`
# covers exactly one label, which is what visa-api.supertravelr.com is, and this
# certificate is in us-east-1 — the region CloudFront requires and the region the
# regional API Gateway domain lives in. One certificate genuinely serves both.
###############################################################################

resource "aws_acm_certificate" "supertravelr" {
  domain_name               = "supertravelr.com"
  subject_alternative_names = ["*.supertravelr.com"]
  validation_method         = "DNS"

  # Renewals issue a new certificate before the old is released, so the
  # distributions never see a gap.
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name      = "supertravelr.com"
    ManagedBy = "terraform"
  }
}

# Blocks until ACM has actually issued. Consumers depend on THIS rather than on
# the certificate resource directly, so Terraform can never point a live
# distribution at a certificate still in PENDING_VALIDATION — CloudFront rejects
# that, mid-apply, after it has already started updating.
resource "aws_acm_certificate_validation" "supertravelr" {
  count           = var.supertravelr_cert_validated ? 1 : 0
  certificate_arn = aws_acm_certificate.supertravelr.arn
  validation_record_fqdns = [
    for o in aws_acm_certificate.supertravelr.domain_validation_options :
    o.resource_record_name
  ]
}

variable "supertravelr_cert_validated" {
  description = <<-EOT
    Two-phase, for the same reason every DNS-validated certificate here is: ACM
    issues only once the validation record resolves, and that record lives in
    Cloudflare, which a different stack manages.

      1. apply with false, then read `supertravelr_acm_validation_record`
      2. add the record to ../cloudflare/dns-records.tf and apply that stack
      3. apply this one again with true

    Leaving it true on the first apply makes the validation resource block until
    it times out.

    TRUE since 2026-09-08: the record is in ../cloudflare/dns-records.tf and the
    certificate reached ISSUED. It stays true — the three distributions below
    reference the VALIDATION resource rather than the certificate, so flipping
    this to false would detach them from their certificate rather than merely
    skipping a check.
  EOT
  type        = bool
  default     = true
}

output "supertravelr_acm_validation_record" {
  description = "Add these to ../cloudflare/dns-records.tf (DNS-only), then set supertravelr_cert_validated = true."
  value = [
    for o in aws_acm_certificate.supertravelr.domain_validation_options : {
      name  = o.resource_record_name
      type  = o.resource_record_type
      value = o.resource_record_value
    }
  ]
}

output "supertravelr_acm_arn" {
  description = "The one certificate for this domain. Consumed by the distributions here and by visa-backend-v1's API Gateway domain."
  value       = aws_acm_certificate.supertravelr.arn
}
