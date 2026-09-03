###############################################################################
# Usage budgets — the tripwires that fire BEFORE any money is spent.
#
# THE PROBLEM THESE SOLVE, WHICH ANOTHER COST BUDGET CANNOT
#
# Every budget in 00-budgets-services.tf measures dollars. Dollars are blind
# below a free tier. July 2026 carried 645 GB and 23M CloudFront requests and
# billed exactly $0.00 — so `shared-prod-cloudfront` read $0.00 ACTUAL / state
# OK for the entire month while the crawl that produced August's $172 was
# already three weeks old. Nothing was broken. A cost budget simply cannot see
# a cliff coming, because on the near side of a cliff the cost is zero and on
# the far side it is all of it at once.
#
# A USAGE budget accrues from the first byte. It is the only budget shape that
# has a gradient across a free tier, which makes it the only one that can warn
# rather than report.
#
# CALIBRATION: limits are set at HALF the free tier, with the first alert at
# 40% of the limit — so the first email arrives at roughly 20% of free-tier
# consumption. On August's traffic that is about four days in, not three weeks.
#
#   CloudFront always-free tier:  1,024 GB   +  10,000,000 requests
#   limit set here:                 500 GB   +   5,000,000 requests
#   first alert at 40%:             200 GB   +   2,000,000 requests
#
# TWO BUDGETS, NOT ONE: a USAGE budget carries a single `limit_unit`, and these
# are measured in GB and Requests respectively. They cannot be combined.
#
# WHY THE FILTERS ARE ENUMERATED BY HAND
#
# There is no `CloudFront: Data Transfer` usage-type GROUP — checked against
# `ce get-dimension-values --dimension USAGE_TYPE_GROUP`, which returns only
# `S3: Data Transfer - CloudFront (Out)`. So the CloudFront usage types have to
# be listed individually, one per billing region.
#
# The list below is CloudFront's complete billing-region set as of 2026-09 and
# matches exactly what August's bill actually contained. THE FRAGILITY IS REAL:
# if AWS adds a billing region, traffic there falls outside this filter and
# this budget under-reports. That is precisely why 08-cloudfront-alarms.tf
# exists alongside it — those alarms read the CloudFront metric directly and
# have no region list to fall out of date.
###############################################################################

locals {
  # CloudFront bills egress and requests per region prefix. Both budgets below
  # derive their filters from this one list so the two cannot drift apart.
  cloudfront_billing_regions = [
    "US", "EU", "AP", "JP", "AU", "SA", "IN", "ME", "ZA", "CA",
  ]

  cloudfront_egress_usage_types = [
    for r in local.cloudfront_billing_regions : "${r}-DataTransfer-Out-Bytes"
  ]

  # Tier2 is HTTPS, Tier1 is HTTP. Both are counted: a crawler that speaks
  # plain HTTP costs the same as one that does not, and August contained
  # 2.9M Tier1 requests alongside the 21M Tier2.
  cloudfront_request_usage_types = concat(
    [for r in local.cloudfront_billing_regions : "${r}-Requests-Tier2-HTTPS"],
    [for r in local.cloudfront_billing_regions : "${r}-Requests-Tier1"],
  )
}

# ──────────────────────────────────────────────────────────────────────────────
# CloudFront egress, measured in GB.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_budgets_budget" "cloudfront_egress_usage" {
  provider     = aws.billing
  name         = "shared-${var.env}-cf-bytes-usage"
  budget_type  = "USAGE"
  limit_amount = tostring(var.cloudfront_egress_gb_limit)
  limit_unit   = "GB"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "UsageType"
    values = local.cloudfront_egress_usage_types
  }

  # 40% first, deliberately low. The whole point is to hear about this while it
  # is still free, so the threshold is set against ZERO expected usage rather
  # than against a normal month. Correct usage on these zones is near enough to
  # nothing that any sustained accrual is abnormal by definition.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 40
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }

  # FORECASTED at 100% is the one that would have caught August earliest — the
  # ramp was visible in the trend long before the total was.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# CloudFront requests, measured in Requests.
#
# For this account the REQUEST budget is the more sensitive of the two: August
# crossed the 10M free requests around the 9th but did not cross 1 TB of egress
# until the 20th. Requests are the leading indicator of a crawl; bytes follow.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_budgets_budget" "cloudfront_requests_usage" {
  provider     = aws.billing
  name         = "shared-${var.env}-cf-requests-usage"
  budget_type  = "USAGE"
  limit_amount = tostring(var.cloudfront_requests_limit)
  limit_unit   = "Requests"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "UsageType"
    values = local.cloudfront_request_usage_types
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 40
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# S3 GET requests.
#
# Half of August's S3 bill was not storage. `APS3-Requests-Tier2` came to $4.74,
# which at $0.0004/1,000 is roughly 11.8 MILLION GET requests — the same crawl
# reaching through CloudFront to the bucket behind it, plus whatever hit the
# public website endpoints directly.
#
# Unlike CloudFront, S3 HAS a usage-type group, so this filter cannot fall out
# of date the way the two above can.
# ──────────────────────────────────────────────────────────────────────────────
# ──────────────────────────────────────────────────────────────────────────────
# S3 egress to the internet — THE BYPASS HOLE.
#
# Every other control in this account assumes traffic arrives through Cloudflare
# and then CloudFront. It does not have to. Nineteen of the thirty-five
# distributions have plain `s3-website` origins, and those bucket endpoints
# answer HTTP 200 directly — verified 2026-09-03:
#
#   http://web.maxinterview.com.production.s3-website...   HTTP 200
#   http://web.geniusjnr.com.production.s3-website...      HTTP 200
#
# A crawler that resolves one of those hostnames skips Cloudflare AND CloudFront
# and pays S3 egress at $0.09/GB with only 100 GB free — a MORE expensive way to
# lose the same money. Not one CloudFront control would see it, because it is
# not CloudFront traffic.
#
# CURRENT USAGE IS 0.5 GB/month, so this is latent rather than active — which is
# exactly when a tripwire is worth setting, and exactly the shape of July 2026:
# 645 GB accruing quietly at $0.00 while nothing watched the gradient.
#
# 50 GB is half the 100 GB free allowance, alerting at 40% — so the first email
# lands around 20 GB, roughly 40x current usage and still free.
#
# THIS REPLACES THREE CLOUDWATCH ALARMS THAT COULD NOT EXIST. They used
# `SEARCH()` to cover every distribution without enumerating any, which is a
# genuinely better shape — and CloudWatch rejects it:
#
#   ValidationError: SEARCH is not supported on Metric Alarms.
#
# SEARCH works in GetMetricData and in dashboards, which is how it was verified,
# and not in PutMetricAlarm. The coverage was recovered rather than rebuilt: the
# two CloudFront usage budgets above filter on UsageType, which is
# DISTRIBUTION-AGNOSTIC — they already cover all thirty-five distributions and
# any created later, which was the entire point of the SEARCH alarms. Only the
# S3 hole was uniquely theirs, and a usage budget closes it with no new
# machinery.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_budgets_budget" "s3_internet_egress_usage" {
  provider     = aws.billing
  name         = "shared-${var.env}-s3-egress-usage"
  budget_type  = "USAGE"
  limit_amount = tostring(var.s3_direct_egress_gb_limit)
  limit_unit   = "GB"
  time_unit    = "MONTHLY"

  cost_filter {
    name = "UsageTypeGroup"
    # A usage-type GROUP, not an enumerated list of regional usage types — so
    # unlike the CloudFront budgets above, this one cannot be out-flanked by a
    # new AWS region.
    values = ["S3: Data Transfer - Internet (Out)"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 40
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }
}

resource "aws_budgets_budget" "s3_requests_usage" {
  provider     = aws.billing
  name         = "shared-${var.env}-s3-requests-usage"
  budget_type  = "USAGE"
  limit_amount = tostring(var.s3_requests_limit)
  limit_unit   = "Requests"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "UsageTypeGroup"
    values = ["S3: API Requests - Standard"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 40
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }
}
