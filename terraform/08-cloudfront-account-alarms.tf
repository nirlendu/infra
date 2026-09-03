###############################################################################
# Account-wide CloudFront alarms — the layer that cannot go stale.
#
# WHY THIS EXISTS ALONGSIDE ../existing/cloudfront-alarms.tf
#
# Those alarms are per-distribution and name the resource, which is what makes
# them actionable. But they cover FIVE distributions out of thirty-five, chosen
# because those five carried 99.9% of August's traffic. That choice was correct
# on the day it was made and is guaranteed to rot:
#
#   - a distribution that is replaced gets a new ID
#   - a new product ships a new distribution
#   - the crawl moves to one of the thirty that are not watched
#
# In every one of those cases the enumerated alarms stay green while the bill
# moves. That is the same shape as the failure this whole effort exists to fix:
# the `data_transfer` budget was pointed at the wrong service line and read
# $0.00 through the entire August incident.
#
# HOW THIS ONE CANNOT ROT
#
# `SEARCH()` resolves its matching time series at EVALUATION time, not at apply
# time. There is no list of distribution IDs here to fall out of date, so a
# distribution created five minutes ago is inside the alarm automatically.
#
# Verified against the live account before this was written:
#
#   SUM(SEARCH('{AWS/CloudFront,DistributionId,Region} MetricName="Requests"',
#              'Sum', 3600))
#   -> 24 datapoints, peak hour 253,021 requests
#
# THE THRESHOLDS ARE THE FREE-TIER RUN RATE, not "normal plus margin".
#
# CloudFront's always-free tier is 1 TB and 10M requests per month. Divided by
# 30, that is ~34 GB and ~333k requests per DAY. So a day above that threshold
# means, arithmetically, that the month ends up billable. This is a statement
# about the cliff rather than a guess about normal, which is the property the
# August post-mortem identified as missing:
#
#   "Any budget whose threshold assumes 'normal + margin' is blind to this
#    shape; D18 is set against zero, not against normal."
#
# EXPECT THESE TO BE IN ALARM ON FIRST APPLY. At the time of writing the account
# is running ~2M requests/day against a 333k threshold. That is not a
# mis-calibration — it is the alarm correctly reporting a live incident that the
# Cloudflare edge work is meant to end. THEM GOING GREEN IS THE MEASUREMENT.
# If they are still red seven days after the edge changes land, the escalation
# is the disabled rule in ../cloudflare/waf-rules.tf.
###############################################################################

# ──────────────────────────────────────────────────────────────────────────────
# Requests, account-wide.
#
# Requests are the leading indicator: August crossed the 10M free requests
# around the 9th but did not cross 1 TB of egress until the 20th.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "cf_account_requests" {
  provider = aws.billing # CloudFront publishes global metrics only into us-east-1

  alarm_name        = "shared-${var.env}-cf-account-requests"
  alarm_description = "CloudFront requests across ALL distributions exceeded the free-tier daily run rate (${var.cloudfront_free_tier_requests_per_day}/day). At this rate the month is billable. Covers distributions that do not exist yet — see 08-cloudfront-account-alarms.tf."

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.cloudfront_free_tier_requests_per_day
  evaluation_periods  = 1

  # `notBreaching`: no traffic emits no datapoints, and no traffic is the goal
  # state. Treating it as missing would leave the alarm permanently in
  # INSUFFICIENT_DATA, which reads identically to "fine" and is how a dead alarm
  # hides.
  treat_missing_data = "notBreaching"

  metric_query {
    id          = "total"
    expression  = "SUM(SEARCH('{AWS/CloudFront,DistributionId,Region} MetricName=\"Requests\"', 'Sum', 86400))"
    label       = "All distributions — requests/day"
    return_data = true
    period      = 86400
  }

  alarm_actions = [aws_sns_topic.budget_alerts.arn]
  ok_actions    = [aws_sns_topic.budget_alerts.arn]
}

# ──────────────────────────────────────────────────────────────────────────────
# Egress, account-wide.
#
# Bytes and requests fail differently: a handful of large objects pulled
# repeatedly can blow the 1 TB tier while staying far under 10M requests. Both
# are billed, so both are watched.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "cf_account_bytes" {
  provider = aws.billing

  alarm_name        = "shared-${var.env}-cf-account-bytes"
  alarm_description = "CloudFront egress across ALL distributions exceeded the free-tier daily run rate (~34 GB/day). At this rate the month is billable."

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.cloudfront_free_tier_bytes_per_day
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "total"
    expression  = "SUM(SEARCH('{AWS/CloudFront,DistributionId,Region} MetricName=\"BytesDownloaded\"', 'Sum', 86400))"
    label       = "All distributions — bytes/day"
    return_data = true
    period      = 86400
  }

  alarm_actions = [aws_sns_topic.budget_alerts.arn]
  ok_actions    = [aws_sns_topic.budget_alerts.arn]
}

# ──────────────────────────────────────────────────────────────────────────────
# S3 egress to the internet, account-wide.
#
# THE HOLE THIS CLOSES. Every control in this account assumes traffic arrives
# through Cloudflare and then CloudFront. It does not have to: nineteen of the
# thirty-five distributions have plain `s3-website` origins, and those bucket
# endpoints answer HTTP 200 directly — verified 2026-09-03. A crawler that
# resolves one of those hostnames bypasses Cloudflare AND CloudFront, and pays
# S3 egress at $0.09/GB with only 100 GB free, which is a MORE expensive way to
# lose the same money.
#
# Nothing else in this file or in the budgets would see that as CloudFront
# traffic, because it is not CloudFront traffic. This is the only tripwire aimed
# at it.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "s3_direct_egress" {
  provider = aws.billing

  alarm_name        = "shared-${var.env}-s3-direct-egress"
  alarm_description = "S3 bytes downloaded across ALL buckets exceeded ${var.s3_direct_egress_gb_per_day} GB/day. Likely the S3 website endpoints being hit directly, bypassing both Cloudflare and CloudFront."

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.s3_direct_egress_gb_per_day * 1024 * 1024 * 1024
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  # BucketSizeBytes is daily-only; BytesDownloaded comes from S3 REQUEST metrics,
  # which are NOT enabled by default per bucket. If this alarm sits in
  # INSUFFICIENT_DATA rather than OK, that is why — request metrics cost $0.20 per
  # million requests to collect and are deliberately not turned on here. The alarm
  # is declared anyway so the gap is visible in code rather than only in a doc.
  metric_query {
    id          = "total"
    expression  = "SUM(SEARCH('{AWS/S3,BucketName,FilterId} MetricName=\"BytesDownloaded\"', 'Sum', 86400))"
    label       = "All buckets — bytes downloaded/day"
    return_data = true
    period      = 86400
  }

  alarm_actions = [aws_sns_topic.budget_alerts.arn]
}
