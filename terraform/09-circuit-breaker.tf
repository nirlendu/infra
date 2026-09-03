###############################################################################
# The circuit breaker — the layer that works while you are asleep.
#
# WHAT THIS IS FOR
#
# The August 2026 post-mortem's own conclusion, which this file exists to act
# on: "Adding a twelfth budget would have changed nothing... one Gmail inbox is
# not a control surface." Every detection layer worked. The bill still ran for
# three weeks, and the single worst day ($26.93) happened overnight.
#
# This is also what makes the current strategy safe. The change set that
# accompanies it deliberately leaves the abandoned distributions ENABLED and
# bets that the Cloudflare edge work absorbs the crawl. If that bet is wrong at
# 3am, this is what pulls the plug instead of a person.
#
# HOW IT IS WIRED
#
#   CloudWatch alarm (per distribution, ../existing/cloudfront-alarms.tf)
#     -> SNS budget_alerts topic (already exists, already carries the email)
#       -> this Lambda
#         -> cloudfront:UpdateDistribution { Enabled: false }
#
# It reuses the existing topic rather than creating another, so there is one
# place to subscribe a phone number and one place to look.
#
# THE TERRAFORM CARVE-OUT — read this before changing anything here.
#
# Disabling a distribution from a Lambda is a cloud change made outside
# Terraform, which this workspace otherwise forbids without exception. The
# carve-out is deliberate, narrow, and shaped exactly like the existing one for
# SSM secret values:
#
#   Terraform owns the distribution. The breaker owns ONE field.
#
# The distributions it is allowed to touch carry
# `lifecycle { ignore_changes = [enabled] }` in
# ../existing/generated_cloudfront.tf. Without that, the next apply would
# helpfully re-enable a distribution the breaker had just switched off, in the
# middle of the incident it was switched off for.
#
# The alternative was no breaker. August cost $273 and the breaker costs about
# twenty cents a month.
###############################################################################

# ──────────────────────────────────────────────────────────────────────────────
# Packaging.
#
# Source lives in lambda/circuit-breaker/ as readable Python rather than a
# committed zip — a binary blob in git is exactly the thing nobody reviews.
# ──────────────────────────────────────────────────────────────────────────────
data "archive_file" "circuit_breaker" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/circuit-breaker"
  output_path = "${path.module}/.terraform/circuit-breaker.zip"
}

# ──────────────────────────────────────────────────────────────────────────────
# Execution role.
#
# Scoped to exactly two CloudFront calls and its own log group. Notably NOT
# cloudfront:CreateDistribution or DeleteDistribution: a breaker that can only
# read a config and set one boolean cannot cause a worse incident than the one
# it is responding to.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "circuit_breaker" {
  name = "shared-${var.env}-circuit-breaker"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "circuit_breaker" {
  name = "circuit-breaker"
  role = aws_iam_role.circuit_breaker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid    = "ReadAndDisableDistributions"
        Effect = "Allow"
        # CloudFront is a global service: its resource ARNs carry no region, and
        # UpdateDistribution cannot be scoped by tag (CloudFront distributions
        # do support tags, but UpdateDistribution has no tag condition key).
        # The real containment is the allowlist inside the function, plus the
        # absence of any create/delete permission here.
        Action = [
          "cloudfront:GetDistributionConfig",
          "cloudfront:UpdateDistribution",
        ]
        Resource = "*"
      },
      {
        Sid      = "NotifyBack"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [aws_sns_topic.budget_alerts.arn]
      },
      {
        Sid    = "ReadTheAllowlist"
        Effect = "Allow"
        # ONE parameter, not a prefix. The allowlist is published by ../existing
        # from the CloudFront resources themselves; see the comment on
        # BREAKER_ALLOWLIST_PARAM below for why it is read at invocation.
        Action   = ["ssm:GetParameter"]
        Resource = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.breaker.account_id}:parameter/shared/prod/breaker/allowed-distributions"]
      },
    ]
  })
}

data "aws_caller_identity" "breaker" {}

# ──────────────────────────────────────────────────────────────────────────────
# The function.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_lambda_function" "circuit_breaker" {
  function_name = "shared-${var.env}-circuit-breaker"
  description   = "Disables an allowlisted CloudFront distribution when its cost alarm fires. See 09-circuit-breaker.tf."

  role    = aws_iam_role.circuit_breaker.arn
  handler = "index.handler"
  runtime = "python3.12"

  # arm64 is cheaper per GB-second and this function is invoked a handful of
  # times a year, so the difference is theoretical — but the account standard is
  # arm64 everywhere and an exception here would just be an inconsistency.
  architectures = ["arm64"]

  filename         = data.archive_file.circuit_breaker.output_path
  source_code_hash = data.archive_file.circuit_breaker.output_base64sha256

  # 128 MB and 60s. It makes two API calls.
  memory_size = 128
  timeout     = 60

  environment {
    variables = {
      BREAKER_ARMED = tostring(var.breaker_armed)

      # THE SAFETY PROPERTY, and where it is defined.
      #
      # The authoritative allowlist is published to SSM by ../existing, derived
      # from the same CloudFront resource references its alarms use — so there is
      # exactly one place the breakable set is defined, and a distribution that
      # is REPLACED (new ID) stays covered without this stack being applied again.
      #
      # Read at invocation, not baked in here. A hardcoded list in a second stack
      # goes stale silently: the breaker would refuse to act on the distribution
      # whose alarm just fired, log "not in the allowlist", and look healthy.
      BREAKER_ALLOWLIST_PARAM = "/shared/prod/breaker/allowed-distributions"

      # Static fallback, used only if SSM cannot be read. An SSM outage should
      # degrade the breaker to its last-known list, never disarm it. The three
      # live products are absent from both — see variables.tf.
      BREAKER_ALLOWED_DISTRIBUTIONS = join(",", var.breaker_allowed_distributions)

      BREAKER_NOTIFY_TOPIC_ARN = aws_sns_topic.budget_alerts.arn
    }
  }
}

# 14 days. Long enough to reconstruct an incident, short enough to cost nothing.
resource "aws_cloudwatch_log_group" "circuit_breaker" {
  name              = "/aws/lambda/${aws_lambda_function.circuit_breaker.function_name}"
  retention_in_days = 14
}

# ──────────────────────────────────────────────────────────────────────────────
# Subscription.
#
# The function receives EVERYTHING on the alerts topic — budget notifications,
# RDS events, its own notifications coming back around. That is intentional:
# filtering here would be a second place to keep in sync with the alarms, and
# the function already ignores anything that is not a CloudWatch alarm in the
# ALARM state carrying a DistributionId dimension.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_lambda_permission" "circuit_breaker_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.circuit_breaker.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.budget_alerts.arn
}

resource "aws_sns_topic_subscription" "circuit_breaker" {
  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.circuit_breaker.arn

  depends_on = [aws_lambda_permission.circuit_breaker_sns]
}

# ──────────────────────────────────────────────────────────────────────────────
# Optional: a phone number.
#
# The post-mortem's open item was "route budget + anomaly SNS to something with
# attention — SMS, Slack". Left empty by default because it needs a real number
# and SMS is billed per message; set `alert_sms_number` in tfvars to enable.
#
# The breaker makes this less critical than it was — the plug now gets pulled
# with or without a human — but knowing it happened still matters.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_sns_topic_subscription" "alerts_sms" {
  count = var.alert_sms_number == "" ? 0 : 1

  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "sms"
  endpoint  = var.alert_sms_number
}
