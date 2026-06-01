###############################################################################
# EC2 HOST + EBS + ELASTIC IP + AUTO-RECOVERY + DLM SNAPSHOTS
#
# Lands in the shared public subnet. EBS data volume + EIP survive instance
# replacement, so the host comes back with state intact. The bootstrap script
# is the app's own (var.user_data_path), rendered with the standard vars below.
###############################################################################

# Latest Amazon Linux 2023 ARM AMI — matches t4g.* instance types.
data "aws_ssm_parameter" "al2023_arm" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  user_data = templatefile(var.user_data_path, merge({
    aws_region    = data.aws_region.current.name
    name_prefix   = var.name_prefix
    env           = var.env
    shared_env    = var.shared_env
    git_repo_url  = var.git_repo_url
    git_ref       = var.git_ref
    domain        = var.domain
    caddy_email   = var.alert_email
    backup_bucket = aws_s3_bucket.backups.id
    data_mount    = local.data_mount
  }, var.user_data_vars))
}

resource "aws_eip" "host" {
  domain = "vpc"
  tags   = { Name = "${var.name_prefix}-${var.env}-eip" }
}

resource "aws_ebs_volume" "data" {
  availability_zone = local.availability_zone
  size              = var.data_volume_size_gb
  type              = "gp3"
  encrypted         = true

  tags = {
    Name    = "${var.name_prefix}-${var.env}-data"
    Backup  = "daily" # picked up by DLM
    Purpose = "${var.name_prefix}-stateful-data"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_instance" "host" {
  ami                         = data.aws_ssm_parameter.al2023_arm.value
  instance_type               = var.instance_type
  subnet_id                   = local.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.host.id]
  iam_instance_profile        = aws_iam_instance_profile.instance.name
  availability_zone           = local.availability_zone
  associate_public_ip_address = false

  credit_specification {
    cpu_credits = "standard" # no Unlimited surprise charge
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 10
    encrypted             = true
    delete_on_termination = true
    tags                  = { Name = "${var.name_prefix}-${var.env}-root" }
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2          # docker containers need IMDS
  }

  user_data                   = local.user_data
  user_data_replace_on_change = false

  tags = { Name = "${var.name_prefix}-${var.env}-host" }

  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [
    aws_security_group_rule.rds_from_host,
    aws_ssm_parameter.app_db_password,
    aws_ssm_parameter.app_db_name,
    aws_ssm_parameter.app_db_user,
    aws_ssm_parameter.app_secret,
  ]
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/xvdh"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.host.id

  stop_instance_before_detaching = true
}

resource "aws_eip_association" "host" {
  instance_id   = aws_instance.host.id
  allocation_id = aws_eip.host.id
}

# ── Auto-recovery on system status-check fail (free) ───────────────────────────
resource "aws_cloudwatch_metric_alarm" "host_status_check" {
  alarm_name          = "${var.name_prefix}-${var.env}-host-status-check"
  alarm_description   = "Auto-recover instance on system status check failure"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"

  dimensions = { InstanceId = aws_instance.host.id }

  alarm_actions = [
    "arn:aws:automate:${data.aws_region.current.name}:ec2:recover",
    local.shared_alerts_topic,
  ]
}

resource "aws_cloudwatch_metric_alarm" "host_status_check_instance" {
  alarm_name          = "${var.name_prefix}-${var.env}-host-instance-check"
  alarm_description   = "OS-level health degraded — operator should look"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_Instance"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"

  dimensions    = { InstanceId = aws_instance.host.id }
  alarm_actions = [local.shared_alerts_topic]
}

# ── DLM — daily snapshots of any volume tagged Backup=daily ────────────────────
data "aws_iam_policy_document" "dlm_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dlm" {
  name               = "${var.name_prefix}-${var.env}-dlm"
  assume_role_policy = data.aws_iam_policy_document.dlm_assume.json
}

resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "daily" {
  description        = "${var.name_prefix}-${var.env} daily EBS snapshots"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    target_tags = {
      Backup = "daily"
    }

    schedule {
      name = "Daily"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"]
      }

      retain_rule {
        count = var.snapshot_retention_days
      }

      copy_tags = true
      tags_to_add = {
        SnapshotCreator = "dlm"
      }
    }
  }
}
