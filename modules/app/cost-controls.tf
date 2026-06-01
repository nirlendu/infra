###############################################################################
# APP-LEVEL COST CONTROLS — layered on top of shared-infra's account-wide
# budgets (see personal/infra/COST-GUARDRAILS.md, layers D8 + D10–D12):
#   1. Tag-filtered budget — counts ONLY resources tagged Project=<name_prefix>.
#   2. NetworkOut alarm — egress spike (the #1 silent bill multiplier).
#   3. CPU alarm — sustained high CPU (runaway loop / compromise).
#   4. EBS write-IOPS storm alarm.
###############################################################################

# 1) Tag-filtered budget. Relies on the root provider's
#    default_tags { Project = <name_prefix> } being set on every resource.
resource "aws_budgets_budget" "app_total" {
  name         = "${var.name_prefix}-${var.env}-total"
  budget_type  = "COST"
  limit_amount = tostring(var.app_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:Project$%s", var.name_prefix)]
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
}

# 2) Egress runaway alarm — alarm if 5-min average NetworkOut > 5 MB/s for 15 min.
resource "aws_cloudwatch_metric_alarm" "host_network_out" {
  alarm_name          = "${var.name_prefix}-${var.env}-network-out-high"
  alarm_description   = "EC2 NetworkOut sustained > 5 MB/s. Possible data exfil / runaway egress."
  namespace           = "AWS/EC2"
  metric_name         = "NetworkOut"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 5 * 1024 * 1024 * 300 # 5 MB/s × 300 s = 1.5 GB per window
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions    = { InstanceId = aws_instance.host.id }
  alarm_actions = [local.shared_alerts_topic]
}

# 3) Sustained-high-CPU alarm — 90% for 30 min = likely runaway loop.
resource "aws_cloudwatch_metric_alarm" "host_cpu_sustained" {
  alarm_name          = "${var.name_prefix}-${var.env}-cpu-sustained-high"
  alarm_description   = "EC2 CPU > 90% for 30 minutes. Likely runaway loop."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 6 # 30 minutes
  threshold           = 90
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions    = { InstanceId = aws_instance.host.id }
  alarm_actions = [local.shared_alerts_topic]
}

# 4) Disk-write IOPS storm — sustained 2k IOPS on gp3 (baseline 3k).
resource "aws_cloudwatch_metric_alarm" "host_ebs_write_iops" {
  alarm_name          = "${var.name_prefix}-${var.env}-ebs-write-storm"
  alarm_description   = "Data volume write IOPS > 2000 sustained — approaching gp3 baseline; possible runaway writes."
  namespace           = "AWS/EBS"
  metric_name         = "VolumeWriteOps"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 6          # 30 minutes
  threshold           = 2000 * 300 # 2k IOPS × 300 s
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions    = { VolumeId = aws_ebs_volume.data.id }
  alarm_actions = [local.shared_alerts_topic]
}
