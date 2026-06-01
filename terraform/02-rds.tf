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

  auto_minor_version_upgrade      = true
  deletion_protection             = true
  skip_final_snapshot             = false
  final_snapshot_identifier       = "shared-${var.env}-postgres-final"
  performance_insights_enabled    = false
  monitoring_interval             = 0
  enabled_cloudwatch_logs_exports = [] # never export to CW Logs — ingest is $0.50/GB

  apply_immediately = false

  lifecycle {
    ignore_changes = [password]
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

  dimensions = { DBInstanceIdentifier = aws_db_instance.shared.id }

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

  dimensions = { DBInstanceIdentifier = aws_db_instance.shared.id }

  alarm_actions = [aws_sns_topic.budget_alerts.arn]
}
