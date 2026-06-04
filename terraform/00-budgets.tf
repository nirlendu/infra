###############################################################################
# 00 — ACCOUNT-WIDE COST GUARDRAILS
#
# Budgets live in shared-infra because they protect the whole AWS account, not
# any individual app. The thresholds should be sized to cover shared-infra +
# every app's expected spend.
#
# Apply this file FIRST before anything billable:
#
#   terraform apply \
#     -target=aws_sns_topic.budget_alerts \
#     -target=aws_sns_topic_subscription.budget_alerts_email \
#     -target=aws_budgets_budget.monthly_cost \
#     -target=aws_budgets_budget.daily_anomaly \
#     -target=aws_cloudwatch_metric_alarm.billing \
#     -target=aws_ce_anomaly_monitor.all_services \
#     -target=aws_ce_anomaly_subscription.email
#
# Confirm the SNS subscription email, then `terraform apply` the rest.
###############################################################################

resource "aws_sns_topic" "budget_alerts" {
  provider = aws.billing
  name     = "shared-${var.env}-budget-alerts"
}

resource "aws_sns_topic_subscription" "budget_alerts_email" {
  provider               = aws.billing
  topic_arn              = aws_sns_topic.budget_alerts.arn
  protocol               = "email"
  endpoint               = var.alert_email
  endpoint_auto_confirms = false
}

# ──────────────────────────────────────────────────────────────────────────────
# 1) Monthly cost budget — 4 thresholds: 50% / 80% / 100% / 120%.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_budgets_budget" "monthly_cost" {
  provider     = aws.billing
  name         = "shared-${var.env}-monthly-cost"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_credit             = false
    include_discount           = true
    include_other_subscription = true
    include_recurring          = true
    include_refund             = false
    include_subscription       = true
    include_support            = true
    include_tax                = true
    include_upfront            = true
    use_amortized              = false
    use_blended                = false
  }

  # Early warning — fires when AWS forecasts you'll cross 25% by month-end.
  # At our $80 cap that's $20, i.e. ~10 days into a normal month.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 25
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 120
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# 2) Daily anomaly budget — same-day alarm on any single-day spike.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_budgets_budget" "daily_anomaly" {
  provider     = aws.billing
  name         = "shared-${var.env}-daily-anomaly"
  budget_type  = "COST"
  limit_amount = tostring(var.daily_anomaly_usd)
  limit_unit   = "USD"
  time_unit    = "DAILY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# 3) CloudWatch billing alarm — redundant alert path.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "billing" {
  provider            = aws.billing
  alarm_name          = "shared-${var.env}-estimated-charges"
  alarm_description   = "Estimated AWS charges crossed the hard ceiling."
  namespace           = "AWS/Billing"
  metric_name         = "EstimatedCharges"
  statistic           = "Maximum"
  period              = 21600
  evaluation_periods  = 1
  threshold           = var.billing_alarm_usd
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = { Currency = "USD" }

  alarm_actions = [aws_sns_topic.budget_alerts.arn]
}

# ──────────────────────────────────────────────────────────────────────────────
# 4) Cost Anomaly Detector — ML baseline per service. Catches NAT/CW Logs
# explosions per service. Free.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_ce_anomaly_monitor" "all_services" {
  provider          = aws.billing
  name              = "shared-${var.env}-all-services"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "email" {
  provider         = aws.billing
  name             = "shared-${var.env}-anomaly-email"
  frequency        = "DAILY" # EMAIL subscribers support DAILY/WEEKLY only; IMMEDIATE is SNS-only
  monitor_arn_list = [aws_ce_anomaly_monitor.all_services.arn]

  subscriber {
    type    = "EMAIL"
    address = var.alert_email
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = [tostring(var.anomaly_threshold_usd)]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }
}
