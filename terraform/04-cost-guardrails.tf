###############################################################################
# 04 — IAM COST GUARDRAILS
#
# A managed IAM policy that DENIES the API calls behind the worst cost
# surprises. Attach it to your operator IAM user / role and you physically
# cannot launch a NAT Gateway, oversized instance, ElastiCache cluster, etc.
#
# The policy is created here but NOT attached to anyone — attaching is a
# deliberate operator step (see README). This way Terraform itself can still
# create the resources it's supposed to (Terraform usually assumes a different
# role / runs under different credentials than your interactive operator).
#
# If you want to opt-in: in IAM Console, attach the ARN this file outputs to
# the IAM user you use day-to-day.
###############################################################################

data "aws_iam_policy_document" "cost_guardrails" {
  # ── #1 Block NAT Gateway. The single biggest "silent bill" trap. ──────────
  statement {
    sid    = "DenyNatGateway"
    effect = "Deny"
    actions = [
      "ec2:CreateNatGateway",
    ]
    resources = ["*"]
  }

  # ── #2 Block ALB / NLB / classic ELB. ─────────────────────────────────────
  statement {
    sid    = "DenyLoadBalancers"
    effect = "Deny"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateTargetGroup",
    ]
    resources = ["*"]
  }

  # ── #3 Block expensive managed services we deliberately don't use. ────────
  statement {
    sid    = "DenyExpensiveManagedServices"
    effect = "Deny"
    actions = [
      "elasticache:CreateCacheCluster",
      "elasticache:CreateReplicationGroup",
      "elasticache:CreateServerlessCache",
      "es:CreateElasticsearchDomain",
      "opensearch:CreateDomain",
      "redshift:CreateCluster",
      "redshift-serverless:CreateWorkgroup",
      "sagemaker:CreateNotebookInstance",
      "sagemaker:CreateEndpoint",
      "sagemaker:CreateDomain",
      "eks:CreateCluster",
      "ecs:CreateCluster",
      "kafka:CreateCluster",   # Amazon MSK — pricey by default
      "kafka:CreateClusterV2",
      "emr:RunJobFlow",
      "memorydb:CreateCluster",
      "neptune-graph:CreateGraph",
      "dax:CreateCluster",
      "kendra:CreateIndex",
      "transfer:CreateServer", # AWS Transfer Family — $0.30/hr per endpoint
      "workspaces:CreateWorkspaces",
    ]
    resources = ["*"]
  }

  # ── #4 Block oversized EC2 instances. Allowlist only what we use. ─────────
  statement {
    sid       = "DenyExpensiveEc2InstanceTypes"
    effect    = "Deny"
    actions   = ["ec2:RunInstances"]
    resources = ["arn:aws:ec2:*:*:instance/*"]

    condition {
      test     = "ForAnyValue:StringNotLike"
      variable = "ec2:InstanceType"
      values = [
        # Allowlist: small/burstable ARM + x86 only.
        "t4g.nano", "t4g.micro", "t4g.small", "t4g.medium", "t4g.large",
        "t3.nano", "t3.micro", "t3.small", "t3.medium",
        "t3a.nano", "t3a.micro", "t3a.small", "t3a.medium",
      ]
    }
  }

  # ── #5 Block oversized EBS volumes (over 200 GB) and provisioned IOPS. ────
  statement {
    sid       = "DenyHugeEbsVolumes"
    effect    = "Deny"
    actions   = ["ec2:CreateVolume"]
    resources = ["*"]

    condition {
      test     = "NumericGreaterThan"
      variable = "ec2:VolumeSize"
      values   = ["200"]
    }
  }

  statement {
    sid       = "DenyProvisionedIopsEbs"
    effect    = "Deny"
    actions   = ["ec2:CreateVolume"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:VolumeType"
      values   = ["io1", "io2"]
    }
  }

  # ── #6 Block oversized RDS instances. ─────────────────────────────────────
  statement {
    sid       = "DenyExpensiveRdsInstanceClasses"
    effect    = "Deny"
    actions   = ["rds:CreateDBInstance", "rds:ModifyDBInstance"]
    resources = ["*"]

    condition {
      test     = "ForAnyValue:StringNotLike"
      variable = "rds:DatabaseClass"
      values = [
        "db.t4g.micro", "db.t4g.small", "db.t4g.medium",
        "db.t3.micro", "db.t3.small", "db.t3.medium",
      ]
    }
  }

  # ── #7 Block Multi-AZ on RDS (doubles every line item). ───────────────────
  statement {
    sid       = "DenyRdsMultiAz"
    effect    = "Deny"
    actions   = ["rds:CreateDBInstance", "rds:ModifyDBInstance"]
    resources = ["*"]

    condition {
      test     = "Bool"
      variable = "rds:MultiAz"
      values   = ["true"]
    }
  }

  # ── #8 Block CloudWatch Logs export from RDS (ingest at $0.50/GB). ────────
  statement {
    sid       = "DenyRdsLogsExport"
    effect    = "Deny"
    actions   = ["rds:CreateDBInstance", "rds:ModifyDBInstance"]
    resources = ["*"]

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "rds:EnableLogTypes"
      values   = ["postgresql", "upgrade", "general", "slowquery", "audit", "error"]
    }
  }
}

resource "aws_iam_policy" "cost_guardrails" {
  name        = "shared-${var.env}-cost-guardrails"
  description = "DENY the AWS API calls behind the worst cost surprises. Attach to operator IAM users."
  policy      = data.aws_iam_policy_document.cost_guardrails.json
}

# Optional helper: a group that already has the policy attached. Operators
# add their IAM user to this group instead of attaching the policy directly.
resource "aws_iam_group" "cost_restricted" {
  name = "shared-${var.env}-cost-restricted"
}

resource "aws_iam_group_policy_attachment" "cost_restricted" {
  group      = aws_iam_group.cost_restricted.name
  policy_arn = aws_iam_policy.cost_guardrails.arn
}
