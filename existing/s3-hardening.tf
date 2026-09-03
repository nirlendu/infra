###############################################################################
# S3 hygiene — stop paying for uploads that never finished.
#
# WHAT THIS DOES, AND DELIBERATELY DOES NOT DO
#
# It adds ONE lifecycle rule per bucket: abort incomplete multipart uploads
# after 7 days. That is all.
#
# No object is expired, no version is deleted, no storage class is transitioned
# and no public-access block is added. Every one of those would be a visible
# change to a legacy site, and the standing instruction is not to change how
# the legacy apps behave until the decision to retire them is made. An
# abandoned multipart upload is invisible to every visitor by definition — it
# is a partial object that was never addressable — so cleaning it up is the one
# S3 change that is unambiguously inside that line.
#
# WHY IT MATTERS
#
# A multipart upload that fails partway leaves its uploaded parts in the bucket,
# billed at full storage rates, forever, and INVISIBLE to `s3 ls` and to the
# console's object listing. It shows up only in the bill and in
# `list-multipart-uploads`. On buckets that have been fed by CI pipelines since
# 2020-2022 — several of which have been failing since May — this is the
# classic silent accumulation.
#
# The audit measured ~192 GB across these buckets and $4.54 of ap-south-1
# storage in August. How much of that is orphaned parts is not knowable from
# the console; this rule makes the question moot going forward.
#
# NOT A PUBLIC-ACCESS BLOCK: these are S3 *website* origins. They are public by
# design and blocking public access would take the sites offline. That finding
# stays open and rides with the retirement decision.
#
# COST: nothing. Lifecycle rules are free; this only ever reduces stored bytes.
###############################################################################

locals {
  # ap-south-1 holds 23 of the 28 buckets and effectively all the storage.
  # Listed by resource reference rather than by name so a rename cannot leave a
  # rule pointing at nothing.
  ap_south_1_buckets = {
    com_serverless_code         = aws_s3_bucket.b_com_serverless_code.id
    web_geniusjnr_com           = aws_s3_bucket.b_web_geniusjnr_com_production.id
    web_suprhealthe_com         = aws_s3_bucket.b_web_suprhealthe_com_production.id
    maxinterview_prod           = aws_s3_bucket.b_maxinterview_prod.id
    contents_indiabackpacks_com = aws_s3_bucket.b_contents_indiabackpacks_com.id
    trips_supertravelr_com      = aws_s3_bucket.b_trips_supertravelr_com_production.id
    visa_supertravelr_com       = aws_s3_bucket.b_visa_supertravelr_com_production.id
    web_nirlendu_com            = aws_s3_bucket.b_web_nirlendu_com_production.id
    contents_suprhealthe_com    = aws_s3_bucket.b_contents_suprhealthe_com.id
    web_maxinterview_com        = aws_s3_bucket.b_web_maxinterview_com_production.id
    learn_geniusjnr_com         = aws_s3_bucket.b_learn_geniusjnr_com_production.id
    web_indiabackpacks_com      = aws_s3_bucket.b_web_indiabackpacks_com_production.id
    contents_dailyapp_co        = aws_s3_bucket.b_contents_dailyapp_co.id
    admin_dailyapp_co           = aws_s3_bucket.b_admin_dailyapp_co_production.id
    in_maxinterview_com         = aws_s3_bucket.b_in_maxinterview_com_production.id
    contents_maxinterview_com   = aws_s3_bucket.b_contents_maxinterview_com.id
    web_supertravellr_com       = aws_s3_bucket.b_web_supertravellr_com_production.id
    web_plusfoods_in            = aws_s3_bucket.b_web_plusfoods_in.id
    practise_geniusjnr_com      = aws_s3_bucket.b_practise_geniusjnr_com_production.id
    web_superwomn_com           = aws_s3_bucket.b_web_superwomn_com_production.id
    web_bettermoney_in          = aws_s3_bucket.b_web_bettermoney_in_production.id
    web_dailyapp_co             = aws_s3_bucket.b_web_dailyapp_co_production.id
    elasticbeanstalk_ap_south_1 = aws_s3_bucket.b_elasticbeanstalk_ap_south_1_419105693501.id
  }

  us_west_2_buckets = {
    masterclub_web_assets = aws_s3_bucket.b_app_masterclub_web_assets_production.id
    masterclub_contents   = aws_s3_bucket.b_app_masterclub_contents.id
    user_assets           = aws_s3_bucket.b_app_user_assets_production.id
    masterclub_videos     = aws_s3_bucket.b_app_masterclub_videos.id
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# ap-south-1 — where the storage is.
#
# `filter {}` with no predicate is required, not optional: without a filter
# block the AWS provider rejects the rule, and with a `prefix = ""` filter some
# provider versions produce a permanent diff. An empty filter means "every
# object", which is what an abort rule wants.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_s3_bucket_lifecycle_configuration" "ap_south_1" {
  for_each = local.ap_south_1_buckets

  provider = aws.ap_south_1
  bucket   = each.value

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    filter {}

    # 7 days. Long enough that a genuinely slow upload over a bad connection
    # is never cut off; short enough that a CI job which died in March is not
    # still being billed in September.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# us-west-2 — the masterclub buckets, including 437 MB of video.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_s3_bucket_lifecycle_configuration" "us_west_2" {
  for_each = local.us_west_2_buckets

  provider = aws.us_west_2
  bucket   = each.value

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# us-east-1 — the personal `nirlendu` bucket (9.5 GB).
#
# This one already carries a lifecycle rule, so it is NOT declared here: a
# second aws_s3_bucket_lifecycle_configuration for the same bucket does not
# merge, it REPLACES, and would silently delete whatever rule is already there.
# Left alone deliberately.
# ──────────────────────────────────────────────────────────────────────────────
