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

# __generated__ by Terraform from "arn:aws:acm:us-east-1:419105693501:certificate/523f8d17-66ef-4dd9-b862-8f786b0e689b"
resource "aws_acm_certificate" "c_nirlendu_com" {
  certificate_authority_arn = null
  certificate_body          = null
  certificate_chain         = null
  domain_name               = "nirlendu.com"
  early_renewal_duration    = null
  key_algorithm             = "RSA_2048"
  private_key               = null # sensitive
  subject_alternative_names = ["*.nirlendu.com", "nirlendu.com"]
  tags                      = {}
  tags_all                  = {}
  validation_method         = "EMAIL"
  options {
    certificate_transparency_logging_preference = "ENABLED"
  }
}

# __generated__ by Terraform from "arn:aws:acm:us-east-1:419105693501:certificate/0a0849ba-e174-42ec-b7bf-4b3fd6731712"
resource "aws_acm_certificate" "c_dailyapp_cc" {
  certificate_authority_arn = null
  certificate_body          = null
  certificate_chain         = null
  domain_name               = "dailyapp.cc"
  early_renewal_duration    = null
  key_algorithm             = "RSA_2048"
  private_key               = null # sensitive
  subject_alternative_names = ["*.dailyapp.cc", "dailyapp.cc"]
  tags                      = {}
  tags_all                  = {}
  validation_method         = "EMAIL"
  options {
    certificate_transparency_logging_preference = "ENABLED"
  }
}

# __generated__ by Terraform from "arn:aws:acm:us-east-1:419105693501:certificate/7d33d895-f66b-4790-bfbe-33c2860aa72d"
resource "aws_acm_certificate" "c_suprhealthe_com" {
  certificate_authority_arn = null
  certificate_body          = null
  certificate_chain         = null
  domain_name               = "suprhealthe.com"
  early_renewal_duration    = null
  key_algorithm             = "RSA_2048"
  private_key               = null # sensitive
  subject_alternative_names = ["*.suprhealthe.com", "suprhealthe.com"]
  tags                      = {}
  tags_all                  = {}
  validation_method         = "EMAIL"
  options {
    certificate_transparency_logging_preference = "ENABLED"
  }
}

# __generated__ by Terraform from "arn:aws:acm:us-east-1:419105693501:certificate/c5ac820a-8aa3-4bc8-892c-1c93c6ac6169"
resource "aws_acm_certificate" "c_plusfoods_in" {
  certificate_authority_arn = null
  certificate_body          = null
  certificate_chain         = null
  domain_name               = "plusfoods.in"
  early_renewal_duration    = null
  key_algorithm             = "RSA_2048"
  private_key               = null # sensitive
  subject_alternative_names = ["*.plusfoods.in", "plusfoods.in"]
  tags                      = {}
  tags_all                  = {}
  validation_method         = "EMAIL"
  options {
    certificate_transparency_logging_preference = "ENABLED"
  }
}

# __generated__ by Terraform from "arn:aws:acm:us-east-1:419105693501:certificate/182bf7d1-50f8-4009-bc3c-ef5d2db1d69f"
resource "aws_acm_certificate" "c_superwomn_com" {
  certificate_authority_arn = null
  certificate_body          = null
  certificate_chain         = null
  domain_name               = "superwomn.com"
  early_renewal_duration    = null
  key_algorithm             = "RSA_2048"
  private_key               = null # sensitive
  subject_alternative_names = ["*.superwomn.com", "superwomn.com"]
  tags                      = {}
  tags_all                  = {}
  validation_method         = "EMAIL"
  options {
    certificate_transparency_logging_preference = "ENABLED"
  }
}

# __generated__ by Terraform from "arn:aws:acm:us-east-1:419105693501:certificate/80652e60-d50e-4909-974d-21edfbc3cbe4"
resource "aws_acm_certificate" "c_geniusjnr_com" {
  certificate_authority_arn = null
  certificate_body          = null
  certificate_chain         = null
  domain_name               = "geniusjnr.com"
  early_renewal_duration    = null
  key_algorithm             = "RSA_2048"
  private_key               = null # sensitive
  subject_alternative_names = ["*.geniusjnr.com", "geniusjnr.com"]
  tags                      = {}
  tags_all                  = {}
  validation_method         = "EMAIL"
  options {
    certificate_transparency_logging_preference = "ENABLED"
  }
}

# __generated__ by Terraform from "arn:aws:acm:us-east-1:419105693501:certificate/cfc63882-0326-411a-a07d-39a57bf403e0"
resource "aws_acm_certificate" "c_indiabackpacks_com" {
  certificate_authority_arn = null
  certificate_body          = null
  certificate_chain         = null
  domain_name               = "indiabackpacks.com"
  early_renewal_duration    = null
  key_algorithm             = "RSA_2048"
  private_key               = null # sensitive
  subject_alternative_names = ["*.indiabackpacks.com", "indiabackpacks.com"]
  tags                      = {}
  tags_all                  = {}
  validation_method         = "EMAIL"
  options {
    certificate_transparency_logging_preference = "ENABLED"
  }
}

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

# __generated__ by Terraform from "arn:aws:acm:us-east-1:419105693501:certificate/bcb01d4b-04db-4990-9524-1f4bbbafef0c"
resource "aws_acm_certificate" "c_bettermoney_in" {
  certificate_authority_arn = null
  certificate_body          = null
  certificate_chain         = null
  domain_name               = "bettermoney.in"
  early_renewal_duration    = null
  key_algorithm             = "RSA_2048"
  private_key               = null # sensitive
  subject_alternative_names = ["*.bettermoney.in", "bettermoney.in"]
  tags                      = {}
  tags_all                  = {}
  validation_method         = "EMAIL"
  options {
    certificate_transparency_logging_preference = "ENABLED"
  }
}
