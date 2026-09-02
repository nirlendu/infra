###############################################################################
# 02 — SHARED RDS POSTGRES
#
# db.t4g.small single-AZ. ~$26/mo all-in. Hosts one database per consumer app.
# App user-data bootstraps its own DB + role on first boot using the master
# password (read from /shared/rds/master_password via the app's IAM role).
###############################################################################

resource "random_password" "rds_master" {
  # Alphanumeric only — password ends up in a postgresql:// URL, so any
  # URL-reserved char would break parsing.
  length  = 40
  special = false
}

resource "aws_db_subnet_group" "shared" {
  name        = "shared-${var.env}-postgres"
  description = "Shared Postgres subnet group (single-AZ in use)."
  subnet_ids  = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

resource "aws_db_parameter_group" "shared" {
  name   = "shared-${var.env}-pg16"
  family = "postgres16"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
    # STATIC parameter — it cannot take effect without a reboot, so AWS stores it
    # as `pending-reboot` regardless of what is asked for. Omitting apply_method
    # gets the provider default `immediate`, which then reads back as drift on
    # every plan forever and would be rejected on the way in.
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }
}

resource "aws_db_instance" "shared" {
  identifier     = "shared-${var.env}-postgres"
  engine         = "postgres"
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class

  db_name  = "postgres" # default admin DB; app DBs created at app bootstrap
  username = "shared_admin"
  password = random_password.rds_master.result
  port     = 5432

  allocated_storage     = var.rds_storage_gb
  max_allocated_storage = var.rds_storage_max_gb # hard cap on autoscale
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.shared.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.shared.name
  availability_zone      = var.availability_zone
  multi_az               = false
  publicly_accessible    = false

  backup_retention_period = var.rds_backup_retention_days
  backup_window           = "07:00-08:00"
  maintenance_window      = "sun:08:30-sun:09:30"

  auto_minor_version_upgrade = true
  deletion_protection        = true
  skip_final_snapshot        = false
  final_snapshot_identifier  = "shared-${var.env}-postgres-final"

  # Keep the automated backups if the instance is ever deleted.
  #
  # Terraform's default is `true`, which discards every automated backup the
  # moment the instance goes — leaving only the final snapshot, a single point in
  # time. Fourteen days of point-in-time recovery would disappear at exactly the
  # moment somebody most wants it, and deletion protection only makes that harder
  # to do by accident, not impossible.
  #
  # Retained backups keep costing their storage and can be deleted deliberately
  # later. That is the right way round when the backups ARE the recovery story.
  delete_automated_backups = false

  # Snapshots inherit the instance's tags, so a restored or orphaned snapshot can
  # still be attributed. Free, and the alternative is an untagged snapshot nobody
  # can place months later.
  copy_tags_to_snapshot           = true
  performance_insights_enabled    = false
  monitoring_interval             = 0
  enabled_cloudwatch_logs_exports = [] # never export to CW Logs — ingest is $0.50/GB

  apply_immediately = false

  lifecycle {
    # `engine_version` alongside `password` because AWS owns the minor version,
    # not this file. `auto_minor_version_upgrade = true` above means AWS patches
    # 16.x whenever it chooses — it moved 16.12 -> 16.13 unannounced — and any
    # value pinned here becomes a plan to DOWNGRADE, which RDS refuses outright.
    # The stack then cannot apply at all, which is how a Postgres patch level
    # ended up blocking an unrelated CloudFront budget in this same stack.
    #
    # Ignoring it says the true thing: the variable expresses intent at CREATE
    # time (major 16, AWS picks the minor) and AWS owns it from then on. A major
    # upgrade is a separate, deliberate operation needing
    # `allow_major_version_upgrade` — it will not happen behind this.
    ignore_changes = [password, engine_version]
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Alert when shared RDS is running out of disk. Cheap insurance: prevents an
# app's runaway INSERT from filling the volume past the autoscale cap.
# Threshold = 20% of allocated storage, in bytes.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  alarm_name          = "shared-${var.env}-rds-low-disk"
  alarm_description   = "Shared Postgres has < 20% free storage left."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.rds_storage_gb * 1024 * 1024 * 1024 * 0.2
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "missing"

  dimensions = { DBInstanceIdentifier = aws_db_instance.shared.identifier }

  alarm_actions = [aws_sns_topic.budget_alerts.arn]
}

# ──────────────────────────────────────────────────────────────────────────────
# Alert when connection count approaches db.t4g.small's ~225 limit.
# Catches the "we added another app and now they're starving each other" case
# before it becomes an outage.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "shared-${var.env}-rds-high-connections"
  alarm_description   = "Shared Postgres connection count is approaching the instance limit."
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 150 # ~70% of db.t4g.small's default max_connections
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"

  dimensions = { DBInstanceIdentifier = aws_db_instance.shared.identifier }

  alarm_actions = [aws_sns_topic.budget_alerts.arn]
}

# ──────────────────────────────────────────────────────────────────────────────
# CPU and memory on the shared instance.
#
# These two were missing, which mattered more here than on a dedicated instance:
# db.t4g.small is shared by every product, so one runaway query does not degrade
# one app — it degrades all of them, and the first symptom anybody sees is an
# unrelated service timing out.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "shared-${var.env}-rds-cpu-high"
  alarm_description   = "Shared Postgres CPU sustained high. On a shared instance this degrades every product at once."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3 # 15 minutes — a vacuum or a migration is not an incident
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"

  dimensions = { DBInstanceIdentifier = aws_db_instance.shared.identifier }

  alarm_actions = [aws_sns_topic.budget_alerts.arn]
  ok_actions    = [aws_sns_topic.budget_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_memory" {
  alarm_name         = "shared-${var.env}-rds-low-memory"
  alarm_description  = "Shared Postgres freeable memory is low. t4g.small has 2 GB and swapping is where latency goes non-linear."
  namespace          = "AWS/RDS"
  metric_name        = "FreeableMemory"
  statistic          = "Average"
  period             = 300
  evaluation_periods = 3
  # 200 MB of 2 GB. Postgres will happily run close to the line; this is the
  # point past which the page cache stops absorbing reads.
  threshold           = 200 * 1024 * 1024
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "missing"

  dimensions = { DBInstanceIdentifier = aws_db_instance.shared.identifier }

  alarm_actions = [aws_sns_topic.budget_alerts.arn]
  ok_actions    = [aws_sns_topic.budget_alerts.arn]
}

# ──────────────────────────────────────────────────────────────────────────────
# RDS event subscription — the cheapest data-loss insurance available.
#
# CloudWatch metrics say how the instance is PERFORMING. They say nothing about
# whether a backup succeeded, whether storage autoscaling hit its cap, or whether
# somebody started a deletion. RDS publishes those as events, and a subscription
# to them is free.
#
# `low storage` matters most here: `max_allocated_storage` caps autoscale at
# 50 GB, and an instance that reaches its cap stops accepting writes. The
# FreeStorageSpace alarm catches the slope; this catches the wall.
#
# `backup` is the one that bears directly on not losing data — a failed automated
# backup is otherwise completely silent until the day you need it.
# ──────────────────────────────────────────────────────────────────────────────
resource "aws_db_event_subscription" "shared" {
  name      = "shared-${var.env}-rds-events"
  sns_topic = aws_sns_topic.budget_alerts.arn

  source_type = "db-instance"
  source_ids  = [aws_db_instance.shared.identifier]

  # Only the categories where an email means something. Checked against AWS's
  # event-message table rather than subscribed to wholesale:
  #
  #   backup       — DROPPED. Its three events are "Backing up DB instance" and
  #                  "Finished DB instance backup", which fire on every routine
  #                  automated backup. That is ~60 mails a month of pure success,
  #                  and it does not even contain a backup-FAILURE event, which was
  #                  the reason for wanting it. A failure surfaces under `failure`.
  #   notification — DROPPED. 24 events, most a bare {{message}}. Low signal.
  #   maintenance  — DROPPED. 19 events, and `auto_minor_version_upgrade = true`
  #                  means patch notices arrive routinely.
  #
  # What is left is the set where the right response is obvious:
  #
  #   low storage  — "Allocated storage has been exhausted", free-capacity-low.
  #                  The wall that the FreeStorageSpace alarm's slope leads to.
  #   availability — includes "storage-full threshold, database has been shut down".
  #   failure      — 32 events, including one that literally recommends a
  #                  point-in-time restore.
  #   deletion     — "DB instance deleted." One event, and the one that would
  #                  matter most on the day it arrives.
  event_categories = [
    "availability",
    "deletion",
    "failure",
    "low storage",
  ]
}
