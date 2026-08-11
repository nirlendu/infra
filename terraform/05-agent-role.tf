###############################################################################
# 05 — THE `agent` ROLE
#
# One role, assumed by the deploy agent. Full reasoning in ../AGENT-ROLE-PLAN.md.
# The short version, because the shape of this file only makes sense if you know
# these five things:
#
# 1. POSTURE: ALLOWLIST, NOT DENYLIST.
#    This account is not clean. It holds a decade of live production for other
#    projects — daily, masterclub, supertravelr, maxinterview, geniusjnr,
#    indiabackpacks, bettermoney, an ap-south-1 Elastic Beanstalk. A
#    "PowerUserAccess minus some denies" role reaches ALL of it, because a
#    denylist is only ever as good as your memory of what's in the account, and
#    there are twelve years of things in here that nobody will enumerate
#    correctly. So: the agent is granted the specific services and the specific
#    named resources authoxi needs. Everything else does not exist to it.
#    Unknown-unknowns fail CLOSED. The Deny policy is defence in depth on top of
#    that — it is not the boundary.
#
# 2. THE AGENT DEPLOYS; IT DOES NOT BOOTSTRAP.
#    authoxi's stack creates 5 IAM roles, and every IAM write is denied here. So
#    the FIRST `terraform apply` is a human's (as admin) — it creates the roles,
#    the budget, the buckets, the versioning, the lifecycle rules. After that a
#    deploy is an ECS task-definition + service diff that touches none of them,
#    and the agent's apply succeeds. If someone edits authoxi's iam.tf (or the
#    budget, or a lifecycle rule), the agent's apply fails with AccessDenied.
#    That is the tripwire working, not a bug — go and look at the diff.
#
# 3. SCOPE IS authoxi ONLY, DELIBERATELY.
#    agentlox is NOT in this allowlist. Its instance role (agentlox/infra/
#    terraform/02-iam.tf:70) holds a STANDING wildcard grant to /shared/<env>/*,
#    which includes the RDS master password. Deploying agentlox requires
#    iam:PassRole onto that role. No condition key separates "pass this role to
#    the instance Terraform manages" from "pass it to an instance I control" — so
#    for agentlox, *the permission to deploy IS the permission to read every
#    database password in the account*. That's a prerequisite, not a policy
#    problem: port authoxi's bootstrap/runtime role split over to agentlox
#    (agentlox's own TODO already proposes it), then add it here. Until then the
#    "AgentloxPivot" deny below blocks the roads into it.
#
# 4. THE PERMISSIONS BOUNDARY IS THE REAL CEILING.
#    Effective permissions = identity policies ∩ boundary. So even if someone
#    later attaches AdministratorAccess to this role, it STILL cannot exceed the
#    boundary. That's the property worth having: the cap survives a future
#    mistake made under deadline pressure.
#
# 5. WHY THIS IS SPLIT INTO FOUR POLICIES.
#    A managed IAM policy caps at 6,144 characters, and a permissions boundary
#    must be ONE managed policy. So the boundary is a COMPACT ceiling (service
#    list + the critical denies) and the fine-grained resource scoping lives in
#    the identity policies, split in two to stay under the limit. If you add to
#    these, watch that limit — you will hit it before you expect to.
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

variable "agent_trusted_principal_arns" {
  description = <<-EOT
    ArnLike patterns for who may assume the `agent` role — matched against
    aws:PrincipalArn, so wildcards are expected and intended.

    Default: the IAM Identity Center AdministratorAccess role, matched by pattern
    so it survives the permission set being recreated (the trailing 16 hex chars
    are regenerated each time).

    GitHub OIDC for unattended CI is PLAN Phase 4: it adds a SECOND trust
    statement and changes NO permissions. That is the point of the design — going
    unattended never requires loosening anything.
  EOT
  type        = list(string)
  default     = ["arn:aws:iam::419105693501:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*"]
}

variable "agent_max_session_seconds" {
  description = "Credential lifetime. 1h: long enough for any apply, short enough that a leaked session expires before you've finished reading the CloudTrail entry."
  type        = number
  default     = 3600
}

locals {
  agent_name = "agent"

  acct   = data.aws_caller_identity.current.account_id
  region = "us-east-1" # authoxi's region. NOT ~/.aws/config's ap-south-1 default.

  authoxi_prefix = "authoxi-${var.env}"

  # Buckets carry a random_id suffix (authoxi-prod-web-<hex>), so they are scoped
  # by ARN PREFIX. Checked against this account's real bucket list: no legacy
  # bucket matches these patterns, so the fence is real and not merely nominal.
  authoxi_buckets     = ["arn:aws:s3:::${local.authoxi_prefix}-web-*", "arn:aws:s3:::${local.authoxi_prefix}-backups-*"]
  authoxi_bucket_objs = [for b in local.authoxi_buckets : "${b}/*"]
  authoxi_backups     = ["arn:aws:s3:::${local.authoxi_prefix}-backups-*", "arn:aws:s3:::${local.authoxi_prefix}-backups-*/*"]

  tfstate_bucket = "nirlendu-tfstate-419105693501" # versioning confirmed Enabled, 2026-07-14

  # The roles the agent may hand to ECS. NOT bootstrap-exec — that one exists to
  # read the shared RDS master password, and passing it is road #2 (PLAN §2).
  passable_roles = [
    "arn:aws:iam::${local.acct}:role/${local.authoxi_prefix}-exec",
    "arn:aws:iam::${local.acct}:role/${local.authoxi_prefix}-task",
    "arn:aws:iam::${local.acct}:role/${local.authoxi_prefix}-backup-task",
    "arn:aws:iam::${local.acct}:role/${local.authoxi_prefix}-scheduler",
  ]

  # Services with no region in their ARNs. The region lock must except them or
  # nothing works. HONEST CAVEAT: aws:RequestedRegion does NOT reliably constrain
  # S3 bucket operations, so the region lock is NOT what protects those ap-south-1
  # legacy buckets — the named-bucket allowlist is. This lock exists to stop
  # compute appearing in a region you never look at.
  global_services = ["iam", "cloudfront", "route53", "s3", "budgets", "ce", "sts", "support", "organizations"]
}

# ─────────────────────────────────────────────────────────────────────────────
# TRUST
# ─────────────────────────────────────────────────────────────────────────────

# The `:root` principal here does NOT mean the root USER — that is the single most
# misread line in IAM. It means "this account", delegating the decision to the
# caller's own IAM policy PLUS the condition below. With the ArnLike condition, the
# only thing that can actually assume this role is the Identity Center admin role.
#
# Why pattern-matched and not the literal ARN: Identity Center provisions its roles
# as AWSReservedSSO_<PermissionSetName>_<random16>. That random suffix changes if
# the permission set is ever deleted and recreated — a hardcoded ARN would be a
# landmine that detonates months later, on a day when you're doing something else.
data "aws_iam_policy_document" "agent_assume" {
  statement {
    sid     = "IdentityCenterAdminMayAssume"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.acct}:root"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = var.agent_trusted_principal_arns
    }
  }
}

resource "aws_iam_role" "agent" {
  name = local.agent_name
  # NB: IAM descriptions accept Latin-1 only ([ -~¡-ÿ]).
  # No em-dashes, no smart quotes - CreateRole rejects them with a regex error.
  description          = "Deploy agent for authoxi. Allowlist posture: see 05-agent-role.tf header and infra/AGENT-ROLE-PLAN.md."
  assume_role_policy   = data.aws_iam_policy_document.agent_assume.json
  max_session_duration = var.agent_max_session_seconds
  permissions_boundary = aws_iam_policy.agent_boundary.arn

  tags = {
    Purpose = "agent-deploy"
    Scope   = "authoxi"
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# ALLOW (1/2) — reads, state, secrets, network
# ═════════════════════════════════════════════════════════════════════════════

data "aws_iam_policy_document" "agent_allow_base" {

  # iam:Get*/List* is REQUIRED, not an oversight: `terraform plan` refreshes
  # aws_iam_role.* from state and dies without it. Read-only — every IAM *write*
  # is denied. The side effect is a feature: an agent that edits authoxi's iam.tf
  # gets AccessDenied at apply.
  statement {
    sid = "ReadsForTerraformRefresh"
    actions = [
      "iam:Get*", "iam:List*", "iam:SimulatePrincipalPolicy",
      "ec2:Describe*", # AWS does not support resource-scoping these. Metadata only.
      "ecs:Describe*", "ecs:List*",
      "ecr:Describe*", "ecr:List*", "ecr:GetAuthorizationToken", # must be "*" — it IS the login call
      # GetLifecyclePolicy is NOT covered by ecr:Describe*/List* — it is its own verb, and
      # aws_ecr_lifecycle_policy cannot refresh without it.
      "ecr:GetLifecyclePolicy",
      "cloudfront:Get*", "cloudfront:List*",
      # DescribeFunction, likewise, is not a Get*. The provider calls it once per
      # aws_cloudfront_function to read the DEVELOPMENT stage on every refresh.
      "cloudfront:DescribeFunction",
      "apigateway:GET",
      "logs:Describe*", "logs:Get*", "logs:FilterLogEvents",
      # Tags are a separate verb from Describe on both of these, and terraform reads tags on
      # every managed resource — so a role that can describe but not list tags fails the refresh
      # rather than the apply, which is a confusing place to discover it.
      "logs:ListTagsForResource",
      "servicediscovery:Get*", "servicediscovery:List*",
      "scheduler:Get*", "scheduler:List*",
      "cloudwatch:Describe*", "cloudwatch:Get*", "cloudwatch:List*",
      # The complete read set data.aws_acm_certificate needs: find, describe, the
      # (public) cert body, and its tags. All read-only; no private-key access exists.
      "acm:DescribeCertificate", "acm:ListCertificates", "acm:GetCertificate", "acm:ListTagsForCertificate",
      "budgets:Describe*", "budgets:ViewBudget", "budgets:ListTagsForResource", # reads only; Modify/Delete denied
      "ce:GetCostAndUsage", "ce:GetCostForecast",                               # infra/scripts/cost-audit.sh
      "sts:GetCallerIdentity", "tag:GetResources",
      "sns:Get*", "sns:List*",
    ]
    resources = ["*"]
  }

  # ── Terraform state: PREFIX-SCOPED. This is road #3 (PLAN §2). ────────────
  # Both stacks share one bucket, and Terraform state stores secrets in PLAINTEXT
  # — so `shared/terraform.tfstate` holds the RDS master password in the clear. A
  # bucket-level grant here would hand it over without touching IAM or SSM.
  statement {
    sid       = "TfStateAuthoxiPrefixOnly"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.tfstate_bucket}/authoxi/*"]
  }

  statement {
    sid       = "TfStateListScoped"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.tfstate_bucket}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["authoxi/*", ""]
    }
  }

  # ── SSM: authoxi's own namespace, read/write. ─────────────────────────────
  statement {
    sid = "SsmAuthoxiParams"
    actions = [
      "ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath",
      "ssm:PutParameter", "ssm:DeleteParameter", "ssm:AddTagsToResource",
      "ssm:ListTagsForResource",
    ]
    resources = ["arn:aws:ssm:${local.region}:${local.acct}:parameter/authoxi/*"]
  }

  # ── SSM: DescribeParameters, which cannot be scoped. ──────────────────────
  #
  # It was in the statement above, scoped to parameter/authoxi/*, where it did NOTHING.
  # DescribeParameters is an account-wide LIST call: AWS evaluates it only against `*`, so a
  # resource-scoped grant is silently ineffective — the request is denied and the policy reads
  # as though it should have worked. That is the worst kind of IAM bug, because the fix looks
  # like it is already there.
  #
  # It surfaced on `terraform plan` for authoxi: the AWS provider calls DescribeParameters to
  # refresh metadata for every aws_ssm_parameter it manages, so the plan failed nine times over
  # on four parameters the role could already read and write.
  #
  # WHAT THIS WIDENS, precisely: the ability to LIST parameter names and metadata across the
  # account. Not values — ssm:GetParameter stays scoped to parameter/authoxi/*, and the deny on
  # the shared RDS master password is untouched. Names are not nothing on a shared account, but
  # it is the minimum AWS allows for an action terraform cannot avoid calling.
  statement {
    sid       = "SsmDescribeParametersUnscopable"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }

  # ── SSM shared namespace: READ ONLY — and the master password is DENIED. ──
  # authoxi's main.tf reads /shared/<env>/{vpc,rds,sns}/* to find the shared VPC
  # and DB. It never reads the master password; only the bootstrap ROLE does. This
  # wildcard would cover it, so the deny policy carves it back out. Deny always
  # beats Allow — that is what makes granting the wildcard here safe.
  statement {
    sid       = "SsmSharedReadOnly"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:${local.region}:${local.acct}:parameter/shared/*"]
  }

  # kms:Decrypt only when spent THROUGH SSM — lifted straight from authoxi's own
  # iam.tf. This is not a general decrypt right; it cannot be turned against any
  # other KMS-encrypted thing in the account.
  statement {
    sid       = "KmsDecryptViaSsmOnly"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${local.region}.amazonaws.com"]
    }
  }

  # ── Security groups: authoxi creates its own inside the shared VPC. ───────
  statement {
    sid = "SecurityGroups"
    actions = [
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules", "ec2:CreateTags",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:Region"
      values   = [local.region]
    }
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# ALLOW (2/2) — the app itself: containers, CDN, edge, buckets
# ═════════════════════════════════════════════════════════════════════════════

data "aws_iam_policy_document" "agent_allow_app" {

  # ── authoxi's buckets. Bucket DELETE, object-VERSION delete and versioning-off
  # are denied below — those are the undo button, and no deploy ever needs them.
  statement {
    sid = "AuthoxiBuckets"
    actions = [
      "s3:Get*", "s3:List*",
      "s3:PutObject", "s3:PutObjectAcl", "s3:DeleteObject",
      "s3:PutBucketPolicy", "s3:PutBucketTagging",
      "s3:PutEncryptionConfiguration", "s3:PutLifecycleConfiguration",
      "s3:CreateBucket",
    ]
    resources = concat(local.authoxi_buckets, local.authoxi_bucket_objs)
  }

  # ── ECS. RegisterTaskDefinition cannot be resource-scoped by AWS. What makes
  # that safe is the PassRole allowlist below — NOT the resource ARN.
  statement {
    sid       = "EcsTaskDefinitions"
    actions   = ["ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition"]
    resources = ["*"]
  }

  statement {
    sid = "EcsAuthoxiCluster"
    actions = [
      "ecs:CreateCluster", "ecs:UpdateCluster", "ecs:PutClusterCapacityProviders",
      "ecs:CreateService", "ecs:UpdateService", "ecs:DeleteService",
      "ecs:RunTask", "ecs:StopTask", "ecs:ExecuteCommand",
      "ecs:TagResource", "ecs:UntagResource",
    ]
    resources = [
      "arn:aws:ecs:${local.region}:${local.acct}:cluster/${local.authoxi_prefix}*",
      "arn:aws:ecs:${local.region}:${local.acct}:service/${local.authoxi_prefix}*/*",
      "arn:aws:ecs:${local.region}:${local.acct}:task/${local.authoxi_prefix}*/*",
      "arn:aws:ecs:${local.region}:${local.acct}:task-definition/${local.authoxi_prefix}*:*",
    ]
  }

  # ── PassRole: the whole ballgame. Four roles, and only to ECS/Scheduler. ──
  # bootstrap-exec is absent BY DESIGN (header note 3 / PLAN §2 road 2).
  statement {
    sid       = "PassRoleToEcsOnly"
    actions   = ["iam:PassRole"]
    resources = local.passable_roles
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com", "scheduler.amazonaws.com"]
    }
  }

  # ── ECR: push images. DeleteRepository / BatchDeleteImage / tag-mutability are
  # denied below — that repo holds the rollback SHAs, and it IS the undo button.
  statement {
    sid = "EcrAuthoxiRepo"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload", "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart",
      "ecr:PutLifecyclePolicy", "ecr:TagResource", "ecr:CreateRepository",
    ]
    resources = ["arn:aws:ecr:${local.region}:${local.acct}:repository/${local.authoxi_prefix}*"]
  }

  # ── CloudFront. Tag-scoped: authoxi's provider sets default_tags Project=authoxi
  # and no legacy distribution in this account carries that tag. DeleteDistribution
  # is NOT here — it's denied below.
  statement {
    sid = "CloudFrontExistingAuthoxi"
    actions = [
      "cloudfront:UpdateDistribution", "cloudfront:CreateInvalidation",
      "cloudfront:TagResource", "cloudfront:UpdateOriginAccessControl",
      "cloudfront:UpdateFunction", "cloudfront:PublishFunction",
      "cloudfront:UpdateCachePolicy",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = ["authoxi"]
    }
  }

  # CloudFront FUNCTIONS are not a taggable resource — CreateFunction takes no tags, so the
  # aws:RequestTag/Project condition below can never be satisfied for it and the call is denied
  # no matter what terraform sends. It was grouped with the other Create* verbs, where it looked
  # granted and was not: the same shape of bug as ssm:DescribeParameters scoped to a path.
  #
  # Untagged and unconditioned, therefore, but narrowed by NAME instead — the agent may only
  # create functions in authoxi's own namespace.
  statement {
    sid = "CloudFrontFunctionsUntaggable"
    # The WHOLE lifecycle, not just Create. Every one of these was already granted elsewhere
    # under an aws:ResourceTag/Project condition that a function can never satisfy, so each one
    # fails in turn as terraform walks create -> publish -> associate. Scoped by NAME instead.
    actions = [
      "cloudfront:CreateFunction", "cloudfront:PublishFunction", "cloudfront:UpdateFunction",
      "cloudfront:DeleteFunction", "cloudfront:DescribeFunction", "cloudfront:GetFunction",
      "cloudfront:TestFunction",
    ]
    resources = ["arn:aws:cloudfront::${local.acct}:function/${local.authoxi_prefix}-*"]
  }

  # Create* has no pre-existing resource to carry a tag, so it takes the
  # RequestTag form instead. Terraform's default_tags supplies it.
  statement {
    sid = "CloudFrontCreateTagged"
    actions = [
      "cloudfront:CreateDistribution",
      "cloudfront:CreateCachePolicy", "cloudfront:CreateOriginAccessControl",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = ["authoxi"]
    }
  }

  statement {
    sid     = "ApiGatewayV2"
    actions = ["apigateway:POST", "apigateway:PUT", "apigateway:PATCH", "apigateway:DELETE"]
    resources = [
      "arn:aws:apigateway:${local.region}::/apis*",
      "arn:aws:apigateway:${local.region}::/vpclinks*",
      "arn:aws:apigateway:${local.region}::/tags/*",
    ]
  }

  statement {
    sid = "CloudMapAndScheduler"
    actions = [
      "servicediscovery:Create*", "servicediscovery:Update*",
      "servicediscovery:Delete*", "servicediscovery:TagResource",
      "scheduler:CreateSchedule", "scheduler:UpdateSchedule",
      "scheduler:DeleteSchedule", "scheduler:TagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid = "LogsAndAlarms"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy", "logs:TagResource",
      "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:TagResource",
    ]
    resources = [
      "arn:aws:logs:${local.region}:${local.acct}:log-group:/ecs/${local.authoxi_prefix}*",
      "arn:aws:logs:${local.region}:${local.acct}:log-group:/aws/${local.authoxi_prefix}*",
      "arn:aws:cloudwatch:${local.region}:${local.acct}:alarm:${local.authoxi_prefix}*",
    ]
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# DENY — defence in depth. If the allowlist above is ever loosened by accident,
# these still hold. An explicit Deny can never be overridden by any Allow.
# ═════════════════════════════════════════════════════════════════════════════

data "aws_iam_policy_document" "agent_deny" {

  # ══ A — THE CROWN JEWEL ═════════════════════════════════════════════════
  # /shared/<env>/rds/master-password reaches EVERY app's database in this
  # account — authoxi's own iam.tf header says so. Three roads, all closed.

  statement {
    sid       = "Jewel1DirectRead"
    effect    = "Deny"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:*:${local.acct}:parameter/shared/*/rds/master-password"]
  }

  statement {
    sid       = "Jewel2BootstrapRole"
    effect    = "Deny"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.acct}:role/*bootstrap-exec*"]
  }

  # Road #3. Terraform state stores secrets in PLAINTEXT, so every one of these
  # objects is a credential dump for something the agent has no business touching:
  #   shared/    — the shared RDS master password (once the RDS stack is applied)
  #   existing/  — 237KB of state for the LEGACY production estate (daily, masterclub,
  #                supertravelr, …). Discovered 2026-07-14; I had not known it existed,
  #                which is exactly why the ALLOW is an allowlist. This deny is the
  #                belt to that braces.
  #   agentlox/  — reserved; see header note 3.
  #
  # Unknown FUTURE prefixes are already handled: the allow grant is scoped to
  # `authoxi/*`, so a new prefix is never granted in the first place. This statement
  # only has to cover the ones that exist.
  statement {
    sid     = "Jewel3PlaintextForeignState"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${local.tfstate_bucket}/shared/*",
      "arn:aws:s3:::${local.tfstate_bucket}/existing/*",
      "arn:aws:s3:::${local.tfstate_bucket}/agentlox/*",
    ]
  }

  # ══ A2 — THE agentlox PIVOT (PLAN §2a) ══════════════════════════════════
  # agentlox-<env>-instance holds a STANDING wildcard grant to /shared/<env>/*.
  # These are the ways to spend it without ever calling SSM yourself. Closing them
  # is also why the agent cannot debug the agentlox box over Session Manager —
  # that is the intended outcome, not a regression.
  statement {
    sid    = "AgentloxPivot"
    effect = "Deny"
    actions = [
      "ssm:SendCommand", "ssm:StartSession",
      "ec2:AssociateIamInstanceProfile", "ec2:ReplaceIamInstanceProfileAssociation",
      "ec2:RunInstances",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "NoPassRoleToInstances"
    effect    = "Deny"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.acct}:role/*instance*"]
  }

  # ══ B — THE UNDO BUTTON ═════════════════════════════════════════════════
  # This group IS the downside cap. Everything else the agent can do is a
  # `terraform apply` from git away from being fixed — UNLESS it can destroy the
  # means of fixing it. Nothing here is ever needed by a legitimate deploy.
  #
  # NOTE: s3:PutBucketPolicy and s3:PutLifecycleConfiguration are deliberately NOT
  # in this blanket Deny. authoxi legitimately sets both on its OWN buckets, and an
  # explicit Deny here could not be "re-allowed" for them — Deny always wins. They
  # are fenced with NotResource in "MutateOnlyOwnBuckets" instead.
  statement {
    sid    = "NeverDestroyTheUndoButton"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:PutBucketVersioning", # versioning can never be turned OFF
      "s3:DeleteObjectVersion", # history can never be purged
      "ecr:DeleteRepository",   # the rollback SHAs live here
      "ecr:BatchDeleteImage",
      "ecr:PutImageTagMutability", # immutable tags ARE the rollback guarantee
      "cloudtrail:StopLogging", "cloudtrail:DeleteTrail", "cloudtrail:UpdateTrail",
      "cloudfront:DeleteDistribution",
      "backup:DeleteBackupVault", "backup:DeleteRecoveryPoint",
    ]
    resources = ["*"]
  }

  # Bucket-config writes are allowed ONLY on authoxi's own buckets. NotResource,
  # not a carve-out Allow — see the note above.
  statement {
    sid           = "MutateOnlyOwnBuckets"
    effect        = "Deny"
    actions       = ["s3:PutBucketPolicy", "s3:PutLifecycleConfiguration", "s3:PutEncryptionConfiguration", "s3:PutBucketPublicAccessBlock"]
    not_resources = concat(local.authoxi_buckets, local.authoxi_bucket_objs)
  }

  # The backups bucket is the DR copy. The agent may create it and read it. It may
  # never empty it, and it may never shorten its lifecycle to expire it early.
  statement {
    sid       = "NeverTouchBackupContents"
    effect    = "Deny"
    actions   = ["s3:DeleteObject", "s3:DeleteObjectVersion", "s3:PutLifecycleConfiguration"]
    resources = local.authoxi_backups
  }

  # ══ C — ESCALATION ══════════════════════════════════════════════════════
  # Every IAM write. The role cannot grant itself anything, cannot edit its own
  # boundary, and cannot mint a new role to hide behind.
  statement {
    sid    = "NoIamWrites"
    effect = "Deny"
    actions = [
      "iam:Create*", "iam:Delete*", "iam:Put*", "iam:Update*",
      "iam:Attach*", "iam:Detach*", "iam:Add*", "iam:Remove*",
      "iam:Tag*", "iam:Untag*", "iam:Set*", "iam:ChangePassword",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "NoAssumingOtherRoles"
    effect    = "Deny"
    actions   = ["sts:AssumeRole", "sts:AssumeRoleWithWebIdentity"]
    resources = ["*"]
  }

  statement {
    sid       = "NoAccountLevelChanges"
    effect    = "Deny"
    actions   = ["organizations:*", "account:*", "aws-portal:*"]
    resources = ["*"]
  }

  # ══ D — SPEND + EXFILTRATION ════════════════════════════════════════════
  # The budget is, per authoxi's own variables.tf, "the ONLY guardrail on task
  # size". So the agent must not be able to raise its own ceiling. Reads stay on.
  statement {
    sid       = "CannotRaiseOwnSpendingCap"
    effect    = "Deny"
    actions   = ["budgets:ModifyBudget", "budgets:DeleteBudget", "budgets:CreateBudgetAction", "ce:UpdateAnomalyMonitor", "ce:DeleteAnomalyMonitor"]
    resources = ["*"]
  }

  # The shared DB is not authoxi's to touch, by any route.
  statement {
    sid       = "NeverTouchSharedRds"
    effect    = "Deny"
    actions   = ["rds:Delete*", "rds:Modify*", "rds:Create*", "rds:Reboot*", "rds:Stop*", "rds:Restore*"]
    resources = ["*"]
  }

  # Exfiltration by making something public, or sharing it out of the account.
  statement {
    sid    = "NoPublicOrCrossAccountSharing"
    effect = "Deny"
    actions = [
      "ec2:ModifySnapshotAttribute", "ec2:ModifyImageAttribute",
      "ecr:SetRepositoryPolicy", "rds:ModifyDBSnapshotAttribute",
      "s3:PutAccountPublicAccessBlock",
      "kms:PutKeyPolicy", "kms:ScheduleKeyDeletion",
    ]
    resources = ["*"]
  }

  # Region lock. Global services excepted or nothing works. See the caveat in
  # locals.global_services — this does NOT fence the ap-south-1 legacy buckets
  # (the named-bucket allowlist does). It stops compute appearing in a region you
  # never look at.
  statement {
    sid         = "RegionLock"
    effect      = "Deny"
    not_actions = [for svc in local.global_services : "${svc}:*"]
    resources   = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# BOUNDARY — the ceiling. effective = identity policies ∩ boundary.
#
# COMPACT BY NECESSITY: a managed policy caps at 6,144 chars and a boundary must
# be ONE policy, so this cannot simply be allow+deny concatenated. It doesn't need
# to be: a boundary only has to CAP, not to grant. So it lists the services the
# agent may ever touch, plus the denies that must survive any future edit — the
# crown jewel, the undo button, and escalation. Fine-grained resource scoping
# stays in the identity policies above.
#
# The property this buys: attach AdministratorAccess to this role tomorrow and it
# STILL cannot read the master password, delete the backups, or write IAM.
# ═════════════════════════════════════════════════════════════════════════════

data "aws_iam_policy_document" "agent_boundary" {
  statement {
    sid    = "CeilingServices"
    effect = "Allow"
    actions = [
      "ecs:*", "ecr:*", "s3:*", "cloudfront:*", "apigateway:*",
      "servicediscovery:*", "scheduler:*", "logs:*", "cloudwatch:*",
      "ssm:*", "ec2:*", "acm:*", "sns:*", "tag:*",
      "kms:Decrypt", "iam:Get*", "iam:List*", "iam:PassRole",
      # ListTagsForResource is not a Describe*, and terraform reads tags on every managed
      # resource — so the ceiling has to name it explicitly or the refresh fails inside the
      # boundary even though the base policy allows it. That distinction is visible in the
      # error: "no permissions boundary allows" rather than "no identity-based policy allows",
      # which is the one useful thing AWS tells you about which of the two layers said no.
      "budgets:Describe*", "budgets:ViewBudget", "budgets:ListTagsForResource", "ce:Get*",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "CeilingJewel1"
    effect    = "Deny"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:*:${local.acct}:parameter/shared/*/rds/master-password"]
  }

  statement {
    sid       = "CeilingJewel2"
    effect    = "Deny"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.acct}:role/*bootstrap-exec*", "arn:aws:iam::${local.acct}:role/*instance*"]
  }

  statement {
    sid       = "CeilingJewel3"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::${local.tfstate_bucket}/shared/*"]
  }

  statement {
    sid    = "CeilingUndoButton"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket", "s3:PutBucketVersioning", "s3:DeleteObjectVersion",
      "ecr:DeleteRepository", "ecr:BatchDeleteImage", "ecr:PutImageTagMutability",
      "cloudtrail:*", "backup:Delete*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CeilingEscalation"
    effect = "Deny"
    actions = [
      "iam:Create*", "iam:Delete*", "iam:Put*", "iam:Update*",
      "iam:Attach*", "iam:Detach*", "iam:Add*", "iam:Remove*", "iam:Set*",
      "sts:AssumeRole", "sts:AssumeRoleWithWebIdentity",
      "organizations:*", "account:*",
      "ssm:SendCommand", "ssm:StartSession",
      "ec2:RunInstances", "ec2:AssociateIamInstanceProfile", "ec2:ReplaceIamInstanceProfileAssociation",
      "rds:Delete*", "rds:Modify*", "rds:Create*",
      "budgets:ModifyBudget", "budgets:DeleteBudget",
    ]
    resources = ["*"]
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# POLICIES + ATTACHMENTS
# ═════════════════════════════════════════════════════════════════════════════

resource "aws_iam_policy" "agent_boundary" {
  name        = "${local.agent_name}-permissions-boundary"
  description = "Hard ceiling on the agent role. A future 'just add one permission' edit still cannot exceed this."
  policy      = data.aws_iam_policy_document.agent_boundary.json
}

resource "aws_iam_policy" "agent_allow_base" {
  name        = "${local.agent_name}-allow-base"
  description = "ALLOWLIST 1/2: terraform reads, state (authoxi/* prefix only), SSM, KMS-via-SSM, security groups."
  policy      = data.aws_iam_policy_document.agent_allow_base.json
}

resource "aws_iam_policy" "agent_allow_app" {
  name        = "${local.agent_name}-allow-app"
  description = "ALLOWLIST 2/2: ECS, ECR, PassRole, CloudFront, API GW, Cloud Map, Scheduler, logs, alarms, buckets."
  policy      = data.aws_iam_policy_document.agent_allow_app.json
}

resource "aws_iam_policy" "agent_deny" {
  name        = "${local.agent_name}-security-guardrails"
  description = "DENY: crown jewel, undo button, escalation, spend, exfiltration. Defence in depth behind the allowlist."
  policy      = data.aws_iam_policy_document.agent_deny.json
}

resource "aws_iam_role_policy_attachment" "agent_allow_base" {
  role       = aws_iam_role.agent.name
  policy_arn = aws_iam_policy.agent_allow_base.arn
}

resource "aws_iam_role_policy_attachment" "agent_allow_app" {
  role       = aws_iam_role.agent.name
  policy_arn = aws_iam_policy.agent_allow_app.arn
}

resource "aws_iam_role_policy_attachment" "agent_deny" {
  role       = aws_iam_role.agent.name
  policy_arn = aws_iam_policy.agent_deny.arn
}

# The COST half was already written in 04-cost-guardrails.tf and deliberately left
# unattached: "attaching is a deliberate operator step… Terraform usually runs
# under different credentials than your interactive operator." This role IS that
# case. Reuse it — do not duplicate the NAT / ELB / instance-size denies here.
resource "aws_iam_role_policy_attachment" "agent_cost_guardrails" {
  role       = aws_iam_role.agent.name
  policy_arn = aws_iam_policy.cost_guardrails.arn
}

# ═════════════════════════════════════════════════════════════════════════════
# OUTPUTS
# ═════════════════════════════════════════════════════════════════════════════

output "agent_role_arn" {
  value = aws_iam_role.agent.arn
}

output "agent_profile_snippet" {
  description = "Paste into ~/.aws/config. The region is PINNED — the default profile's ap-south-1 would deploy this to the wrong continent."
  value       = <<-EOT

    [profile authoxi-deploy]
    region           = ${local.region}
    role_arn         = ${aws_iam_role.agent.arn}
    source_profile   = admin
    duration_seconds = ${var.agent_max_session_seconds}

    # then:  AWS_PROFILE=authoxi-deploy make deploy
    #
    # Reminder (PLAN §6): on your laptop this profile is NOT a security boundary.
    # The agent's shell can reach `admin` too. It protects you from ACCIDENTS.
    # The real boundary is Phase 4 — unattended CI via OIDC, where no human admin
    # session exists anywhere near the agent.
  EOT
}
