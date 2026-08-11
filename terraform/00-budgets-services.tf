###############################################################################
# 00b — PER-SERVICE COST TRIPWIRES
#
# Each budget filters on ONE service. They cost about $0.60/mo each beyond
# the first 2 free budgets, but they catch a runaway service the day it
# starts charging — long before the monthly total budget would notice.
#
# Cost of this file: ~$3/mo (5 budgets × ~$0.60 minus 62 free budget-days).
# Value: $33/mo idle NAT Gateway caught in <24 hrs.
###############################################################################

# ──────────────────────────────────────────────────────────────────────────────
# EC2 spend cap. Anything above the expected ~$24 (one t4g.medium) means a
# bigger instance was launched or an extra one started.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_budgets_budget" "ec2" {
  provider     = aws.billing
  name         = "shared-${var.env}-ec2"
  budget_type  = "COST"
  limit_amount = tostring(var.ec2_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = ["Amazon Elastic Compute Cloud - Compute"]
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
}

# ──────────────────────────────────────────────────────────────────────────────
# RDS spend cap. db.t4g.small ≈ $26.28/mo. Above this means someone resized
# the instance or enabled Multi-AZ.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_budgets_budget" "rds" {
  provider     = aws.billing
  name         = "shared-${var.env}-rds"
  budget_type  = "COST"
  limit_amount = tostring(var.rds_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = ["Amazon Relational Database Service"]
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
}

# ──────────────────────────────────────────────────────────────────────────────
# VPC spend cap — set to $1. VPC itself is free. Any spend here means:
#   - NAT Gateway ($32.85/mo idle + $0.045/GB)
#   - VPC Endpoint ($7-15/mo each)
#   - Transit Gateway ($36/mo + attachments)
# Fires on the FIRST DAY of any of these.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_budgets_budget" "vpc" {
  provider     = aws.billing
  name         = "shared-${var.env}-vpc-anti-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.vpc_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = ["Amazon Virtual Private Cloud"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 1
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# ELB anti-budget — set to $1. We never want an ALB/NLB. ALB idle ≈ $16/mo +
# LCUs. NLB idle ≈ $16/mo + NLCUs. Fires same-day.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_budgets_budget" "elb" {
  provider     = aws.billing
  name         = "shared-${var.env}-elb-anti-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.elb_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = ["Elastic Load Balancing"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 1
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Data transfer cap — catches egress runaway. Default $5 ≈ 55 GB beyond the
# 100 GB free tier. Egress is THE most common "silent bill" item.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_budgets_budget" "data_transfer" {
  provider     = aws.billing
  name         = "shared-${var.env}-data-transfer"
  budget_type  = "COST"
  limit_amount = tostring(var.data_transfer_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = ["AWS Data Transfer"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# ECS/Fargate cap — the guardrail that REPLACES the `ecs:CreateCluster` deny
# (removed 2026-07-14; see 04-cost-guardrails.tf #3 for the reasoning).
#
# Fargate has no idle floor to catch: the cluster object is free, and tasks bill
# per vCPU-second. What CAN run away is task SIZE (someone bumps cpu 256 → 4096)
# or task COUNT (an autoscaling rule, or a crash-looping service ECS keeps
# replacing). Neither is expressible as an IAM condition key, so a budget is the
# only enforcement available — which is exactly why this exists.
#
# Default $25 ≈ 2× what authoxi's one 0.25 vCPU / 1 GB ARM task costs (~$8.50/mo)
# plus its public IPv4 (~$3.65/mo). Fires well before a fat task reaches a bill.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_budgets_budget" "ecs" {
  provider     = aws.billing
  name         = "shared-${var.env}-ecs"
  budget_type  = "COST"
  limit_amount = tostring(var.ecs_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = ["Amazon Elastic Container Service"]
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
}
