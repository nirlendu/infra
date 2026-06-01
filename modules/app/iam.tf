###############################################################################
# IAM — instance role: SSM Session Manager, read app + shared SSM params,
# read/write the per-app backup bucket, publish CW metrics, run cost-audit.
#
# SECURITY TRADE-OFF: this role can read the shared RDS master password at first
# boot to provision its own DB+role. A compromise of this host can reach other
# apps' databases. Acceptable pre-revenue; mitigate at scale by moving the app
# to its own RDS or a one-shot bootstrap Lambda. (See cost-guardrails canon.)
###############################################################################

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name_prefix}-${var.env}-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# SSM Parameter Store: read app-owned + shared parameters.
data "aws_iam_policy_document" "ssm_read" {
  statement {
    sid     = "AppSecretsRead"
    actions = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.name_prefix}/${var.env}/*",
    ]
  }

  statement {
    sid     = "SharedReadOnly"
    actions = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/shared/${var.shared_env}/*",
    ]
  }

  statement {
    sid       = "KmsDecryptForSsm"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "ssm_read" {
  name   = "${var.name_prefix}-${var.env}-ssm-read"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.ssm_read.json
}

# Per-app S3 backup bucket.
data "aws_iam_policy_document" "s3_backup" {
  statement {
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
      "s3:ListBucket", "s3:GetBucketLocation",
    ]
    resources = [
      aws_s3_bucket.backups.arn,
      "${aws_s3_bucket.backups.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "s3_backup" {
  name   = "${var.name_prefix}-${var.env}-s3-backup"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.s3_backup.json
}

# Read-only allow-list for the weekly cost-audit script (NOT broad ReadOnlyAccess).
data "aws_iam_policy_document" "cost_audit" {
  statement {
    sid = "CostAuditReadOnly"
    actions = [
      "ec2:DescribeVolumes", "ec2:DescribeSnapshots", "ec2:DescribeInstances",
      "ec2:DescribeAddresses", "ec2:DescribeNatGateways",
      "elasticloadbalancing:DescribeLoadBalancers",
      "rds:DescribeDBInstances", "logs:DescribeLogGroups",
      "s3:ListAllMyBuckets", "s3:ListBucket", "s3:GetBucketLocation",
      "ce:GetCostAndUsage",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cost_audit" {
  name   = "${var.name_prefix}-${var.env}-cost-audit"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.cost_audit.json
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name_prefix}-${var.env}-instance"
  role = aws_iam_role.instance.name
}
