# __generated__ by Terraform
# Please review these resources and move them into your main configuration files.

# __generated__ by Terraform from "arn:aws:acm:us-east-1:419105693501:certificate/15aedeec-578b-4820-9953-e4c92c1abd99"
resource "aws_acm_certificate" "c_maxinterview_com" {
  certificate_authority_arn = null
  certificate_body          = null
  certificate_chain         = null
  domain_name               = "maxinterview.com"
  early_renewal_duration    = null
  key_algorithm             = "RSA_2048"
  private_key               = null # sensitive
  subject_alternative_names = ["*.maxinterview.com", "maxinterview.com"]
  tags                      = {}
  tags_all                  = {}
  # DNS, not EMAIL. The import generator wrote EMAIL for all ten certificates in
  # this file; nine of them really are email-validated, but ACM re-issued this one
  # under DNS validation on 2026-07-01 (`renewal_summary.updated_at`), and state was
  # never reconciled.
  #
  # `validation_method` forces replacement, so the stale value made every plan here
  # read "1 to add, 1 to destroy" — a destroy of a certificate that is ISSUED and
  # attached to FOUR live CloudFront distributions, including maxinterview.com and
  # code.maxinterview.com. ACM refuses to delete a certificate in use, so the apply
  # could only fail partway; the danger was never that it would succeed.
  #
  # Found 2026-09-07 while checking whether this stack was safe to apply before
  # adding a /visa/* behaviour to the supertravelr.com distribution. Nothing about
  # the certificate changed here: this makes the code match what AWS already holds.
  validation_method = "DNS"
  options {
    certificate_transparency_logging_preference = "ENABLED"
  }
}

# REMOVED 2026-10-14: c_superwomn_com, the EMAIL-validated certificate for
# superwomn.com + *.superwomn.com (182bf7d1-...). It EXPIRED on 2026-10-04 — its
# renewal mail was never approved — and cf_superwomn_com kept serving it, which
# only went unnoticed because Cloudflare does not verify the origin certificate.
# Replaced by aws_acm_certificate.domain["superwomn.com"] in domain-acm.tf, DNS-
# validated; the distribution was moved across before this was deleted.
#
# REMOVED 2026-10-14, the last of the EMAIL-validated certificates: c_nirlendu_com
# (523f8d17-...), c_suprhealthe_com (7d33d895-...) and c_geniusjnr_com
# (80652e60-...), each replaced by its domain's entry in domain-acm.tf after
# every distribution here was moved across. agitome.com's (b621b471-...) and
# purvadas.com's (9055def2-...) were never in Terraform; they were imported
# only so that Terraform could delete them.
#
# REMOVED the same day, with their domains decommissioned: c_dailyapp_cc,
# c_indiabackpacks_com, c_bettermoney_in and c_plusfoods_in — all expired, all
# EMAIL-validated, deleted after the seven distributions riding them.

# REMOVED 2026-09-08: c_supertravelr_com, the EMAIL-validated certificate for
# supertravelr.com + *.supertravelr.com (cf0bab96-...).
#
# It was due to expire 2026-10-22 with its managed renewal stuck at
# PENDING_VALIDATION —
# ACM mails five addresses at the domain and a human must approve within 72
# hours, every renewal, forever, and nobody had. All three supertravelr
# distributions rode it, so a lapse would have failed TLS for the legacy site,
# trips.supertravelr.com and supertravelr.com/visa at the same moment.
#
# Replaced by aws_acm_certificate.supertravelr in supertravelr-acm.tf: same two
# names, DNS-validated, renews itself from a record that lives in
# ../cloudflare/dns-records.tf. Every consumer was moved across and the
# certificate confirmed detached (InUseBy empty) before this was deleted.
