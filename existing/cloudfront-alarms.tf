###############################################################################
# Per-distribution CloudFront alarms — the layer that names the resource.
#
# WHY THESE ARE NOT MORE BUDGETS
#
# The August 2026 post-mortem's honest conclusion was that detection did not
# fail: `monthly_cost` was in ALARM at 100% and 120%, `daily_anomaly` was in
# ALARM, and the Cost Anomaly Detector was live at a $3 threshold — for three
# weeks. What every one of those alerts could not say is WHICH RESOURCE. A
# budget knows a service and a dollar figure. It does not know that
# `code.maxinterview.com` is doing 40 million requests while the three live
# products are doing four thousand between them.
#
# These alarms close exactly that gap, and they live in THIS stack rather than
# in ../terraform precisely so they can reference the distributions as
# resources. An alarm that hardcodes `ETX7NAHEKHMR` is an alarm that silently
# stops matching the day a distribution is replaced.
#
# THEY ARE ALSO THE MEASURING INSTRUMENT
#
# The current change set deliberately leaves the abandoned distributions
# ENABLED and bets that the Cloudflare edge work absorbs the crawl instead.
# That bet needs a verdict. These alarms are how it gets one: if origin
# requests stay elevated after the edge changes land, the escalation is
# pre-staged in ../cloudflare/waf-rules.tf as a disabled rule.
#
# COST: CloudWatch gives 10 alarms free per account, then $0.10/alarm/month.
# ../terraform already uses 5, so these 12 put the account at roughly $0.70/mo.
###############################################################################

# The SNS topic is owned by ../terraform and published to SSM so stacks can
# find it without remote-state coupling. Reading it here rather than hardcoding
# the ARN means a topic rebuild does not silently orphan every alarm below.
data "aws_ssm_parameter" "alerts_topic" {
  name = "/shared/prod/sns/alerts-topic-arn"
}

locals {
  # Distributions worth watching, by resource reference rather than by ID.
  #
  # Chosen by measured August traffic: these five carried 99.9% of it. The
  # remaining twenty are quiet enough that an alarm on each would be $2/month
  # of noise — the account-wide usage budgets in ../terraform cover them.
  watched_distributions = {
    code_maxinterview = aws_cloudfront_distribution.cf_code_maxinterview_com.id
    maxinterview      = aws_cloudfront_distribution.cf_maxinterview_com.id
    supertravelr      = aws_cloudfront_distribution.cf_supertravelr_com.id
    geniusjnr         = aws_cloudfront_distribution.cf_geniusjnr_com.id
    trips             = aws_cloudfront_distribution.cf_trips_supertravelr_com.id
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Request volume.
#
# THRESHOLD REASONING: 300,000 requests in an hour, sustained for two hours.
#
# The upper bound of normal is easy to establish here because it was measured —
# the three live products together took ~4,000 requests in all of August, and
# these five legacy distributions should trend toward zero as the edge absorbs
# them. 300k/hour is therefore not "a bit above normal", it is roughly 75x the
# entire month's legitimate traffic, arriving inside one hour.
#
# It is calibrated against the incident rather than against a baseline: August
# peaked at ~250k/hour and sustained 80-120k/hour for days. Two consecutive
# hours above 300k means something is very wrong and is not a deploy.
#
# `treat_missing_data = "notBreaching"`: a distribution with no traffic emits no
# datapoints, and "no traffic" is the goal state here, not an alarm condition.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "cf_requests" {
  for_each = local.watched_distributions

  alarm_name          = "cf-requests-${each.key}"
  alarm_description   = "CloudFront ${each.key}: >300k requests/hour for 2h. Crawl or origin-bypass. Check ../cloudflare cache hit rate first, then whether the *.cloudfront.net domain is being hit directly."
  namespace           = "AWS/CloudFront"
  metric_name         = "Requests"
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 2
  threshold           = 300000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  # CloudFront publishes global metrics only, and only into us-east-1. Both
  # dimensions are required — omitting Region returns no datapoints at all,
  # which presents as a permanently INSUFFICIENT_DATA alarm that looks fine.
  dimensions = {
    DistributionId = each.value
    Region         = "Global"
  }

  alarm_actions = [data.aws_ssm_parameter.alerts_topic.value]
  ok_actions    = [data.aws_ssm_parameter.alerts_topic.value]

  tags = {
    Project   = "shared"
    ManagedBy = "terraform"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Egress volume.
#
# Requests and bytes fail differently and both are billed, so both are watched.
# A request alarm misses the case where a small number of large objects are
# pulled repeatedly — 20 GB in an hour is only ~5,700 requests against a 3.5 MB
# video, which sails under the request threshold while costing more.
#
# 20 GB/hour sustained for two hours would be 28 TB/month if it continued.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "cf_bytes" {
  for_each = local.watched_distributions

  alarm_name          = "cf-bytes-${each.key}"
  alarm_description   = "CloudFront ${each.key}: >20 GB egress/hour for 2h. Large-object scraping or hotlinking."
  namespace           = "AWS/CloudFront"
  metric_name         = "BytesDownloaded"
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 2
  threshold           = 21474836480 # 20 GiB
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = each.value
    Region         = "Global"
  }

  alarm_actions = [data.aws_ssm_parameter.alerts_topic.value]
  ok_actions    = [data.aws_ssm_parameter.alerts_topic.value]

  tags = {
    Project   = "shared"
    ManagedBy = "terraform"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Error rate — the early-warning signal, and the most specific one.
#
# This is the signature of the exact attack that produced the August bill. A
# crawler enumerating URLs that do not exist generates mostly 404s, and a 404 is
# billed identically to a 200: the probe run on 2026-09-03 returned
# `cf-cache-status: MISS` and `x-cache: Error from cloudfront` for a random
# path, meaning a full round trip to be told nothing is there.
#
# A healthy static site sits in the low single digits. Sustained 25% means
# something is walking a URL space rather than reading pages, and it will show
# here BEFORE the volume alarms trip — which is what makes this the one worth
# reading first.
#
# One hour, not two: this metric is cheap to be right about and there is no
# legitimate deploy that produces a quarter 4xx for an hour.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "cf_error_rate" {
  for_each = local.watched_distributions

  alarm_name          = "cf-4xx-${each.key}"
  alarm_description   = "CloudFront ${each.key}: >25% 4xx for 1h. Signature of a URL-space crawl — dead paths are billed like live ones."
  namespace           = "AWS/CloudFront"
  metric_name         = "4xxErrorRate"
  statistic           = "Average"
  period              = 3600
  evaluation_periods  = 1
  threshold           = 25
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = each.value
    Region         = "Global"
  }

  alarm_actions = [data.aws_ssm_parameter.alerts_topic.value]

  tags = {
    Project   = "shared"
    ManagedBy = "terraform"
  }
}
