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

  # ── Which distributions can carry an ERROR-RATE alarm at all ───────────────
  #
  # A fixed error-rate threshold only means something on a distribution whose
  # normal error rate is near zero. Measured over 24h on 2026-09-03/04:
  #
  #   maxinterview        0.0% - 0.1%     healthy
  #   supertravelr        0.0% - 0.1%     healthy
  #   geniusjnr           0.0% - 0.3%     healthy
  #   trips              16.2% - 31.5%    mean 24.9%
  #   code_maxinterview   1.2% - 86.2%    mean 21.8%
  #
  # The first three sit at zero, so any sustained error rate is a real signal.
  # The last two do not, because those sites are partly broken: trips returns
  # 404 at `/` and has for at least a week, and code_maxinterview swings across
  # the whole range hour to hour.
  #
  # The original alarm put a 25% threshold on all five. On trips that bisects
  # the noise band — its 24h MEAN is 24.9% against a 25% threshold — and the
  # result was 10 OK->ALARM transitions in 12 hours, i.e. 10 emails about a
  # condition that had been true and unchanged for a week and was costing
  # nothing. That is precisely the alarm fatigue COST-GUARDRAILS.md's own
  # post-mortem identifies as the reason August ran for three weeks: once a
  # notification is normal, a real one looks exactly like the noise.
  #
  # Raising the threshold until trips stops flapping does not work either. Its
  # daily average was 54.4% on 1 September, so any threshold high enough to
  # silence it (>55%, with hysteresis) is high enough to be decoration — and a
  # rule that cannot fire is the failure mode this repo keeps writing down.
  #
  # So they are EXCLUDED, and the exclusion is the honest answer: a distribution
  # with a 15-55% baseline error rate does not need an alarm, it needs its 404s
  # fixed. Until someone does that, these two are still covered for COST by the
  # Requests and BytesDownloaded alarms below, which is what actually matters
  # here — 4xx responses are small and cheap, and this alarm was only ever an
  # early-warning nicety on top.
  error_rate_distributions = {
    maxinterview = aws_cloudfront_distribution.cf_maxinterview_com.id
    supertravelr = aws_cloudfront_distribution.cf_supertravelr_com.id
    geniusjnr    = aws_cloudfront_distribution.cf_geniusjnr_com.id
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# The circuit breaker's allowlist, published from the resources themselves.
#
# WHY THIS IS NOT JUST A LIST IN THE LAMBDA'S ENVIRONMENT.
#
# The breaker (../terraform/09-circuit-breaker.tf) may only disable a
# distribution named in its allowlist — that is the property that lets it be
# armed by default without being able to touch production. But the allowlist
# started life as hardcoded IDs in a tfvar, which is a SECOND enumeration of the
# same five distributions, in a different stack, that nothing keeps in step.
#
# A CloudFront distribution gets a new ID when it is replaced. The moment that
# happens, the alarms here follow it automatically (they reference the resource),
# and the breaker's hardcoded list does not. The breaker then refuses to act on
# the very distribution the alarm just fired for, logs "not in the allowlist",
# and looks like it is working.
#
# Failing safe is not the same as working. Publishing the list from the same
# resource references the alarms use means there is exactly ONE place the set of
# breakable distributions is defined, and a replacement updates it on the next
# apply of this stack.
#
# The Lambda reads this at INVOCATION, not at deploy: the breaker picks up a new
# ID without needing ../terraform to be applied again.
#
# StringList rather than String: this is a list, and the type says so.
resource "aws_ssm_parameter" "breaker_allowlist" {
  name  = "/shared/prod/breaker/allowed-distributions"
  type  = "StringList"
  value = join(",", values(local.watched_distributions))

  description = "CloudFront distribution IDs the cost circuit breaker may disable. Derived from existing/cloudfront-alarms.tf. The three live products are absent by construction."

  tags = {
    Project   = "shared"
    ManagedBy = "terraform"
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
# The three distributions this applies to sit at 0.0-0.3%, so a sustained 50%
# is not "elevated" — it is more than a hundred times normal, and means
# something is walking a URL space rather than reading pages. It shows here
# BEFORE the volume alarms trip, which is what makes it worth reading first.
#
# ── CALIBRATION, LEARNED THE NOISY WAY (2026-09-04) ──────────────────────────
#
# This was originally 25% over ONE hour, applied to all five watched
# distributions. Both of those were wrong.
#
# 25% bisected trips' normal range (16.2-31.5%, mean 24.9%), so the alarm
# oscillated with the metric: 10 OK->ALARM transitions in 12 hours, 10 emails,
# about a week-old condition that cost nothing. Two changes fix it, and the
# `error_rate_distributions` local above carries the third:
#
#   threshold 25 -> 50   Above every healthy baseline by ~150x, and above the
#                        noise band of any distribution still in scope.
#
#   1 period -> 3        HYSTERESIS. One bad hour no longer pages. A crawl that
#                        matters does not stop after 60 minutes, so requiring
#                        three consecutive hours costs nothing in detection and
#                        removes every single-datapoint flap.
#
# `datapoints_to_alarm` is set equal to `evaluation_periods` deliberately: the
# default "M of N" behaviour would let 3 non-consecutive spikes in any window
# trip it, which is the flapping this is meant to end.
#
# NO ok_actions, unlike the volume alarms. Recovery from an error-rate blip is
# not news, and an OK notification doubles the mail for no added signal — half
# of the 10 emails were the metric falling back under the line.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "cf_error_rate" {
  for_each = local.error_rate_distributions

  alarm_name          = "cf-4xx-${each.key}"
  alarm_description   = "CloudFront ${each.key}: >50% 4xx for 3 consecutive hours. Signature of a URL-space crawl — dead paths are billed like live ones. Baseline for this distribution is under 0.3%."
  namespace           = "AWS/CloudFront"
  metric_name         = "4xxErrorRate"
  statistic           = "Average"
  period              = 3600
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 50
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
