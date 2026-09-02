###############################################################################
# 06 — THE CLOUDFLARE API TOKEN, and the one role allowed to read it
#
# Cloudflare is the real user-facing edge for every domain in this account
# (see ../cloudflare/README.md): every hostname is orange-clouded, so Cloudflare
# serves what it can from its own cache and CloudFront is only an origin. The
# stack that configures it authenticates with CLOUDFLARE_API_TOKEN, which until
# now lived nowhere but an operator's shell.
#
# That is a problem in three directions:
#
#   * it exists on exactly one laptop, so nothing unattended can purge a cache
#     or apply an edge change;
#   * nothing records that it exists, what it is scoped to, or when it was last
#     rotated;
#   * a Cloudflare token is an ACCOUNT-WIDE bearer credential. It can repoint
#     DNS for every domain here. It is the highest-blast-radius secret in this
#     account after the RDS master password, and it was the least managed.
#
# ── The value is NOT in Terraform state, deliberately ─────────────────────────
#
# `aws_ssm_parameter` normally stores its value in state — and state for this
# stack holds the RDS master password in plaintext already, which is precisely
# the thing `05-agent-role.tf` fences off with a prefix-scoped grant. Worse,
# `terraform plan` REFRESHES, and refreshing an `aws_ssm_parameter` reads the
# value back; authoxi's github-oidc.tf carries the same warning for the same
# reason. So a token written here in the normal way would end up readable by
# anything that can read this stack's state or run a plan against it.
#
# Instead: Terraform owns the parameter's EXISTENCE, name, type, tier and
# description. It does not own the value. `ignore_changes = [value]` means the
# placeholder below is written once, on create, and never looked at again.
#
# ── Putting the real token in ─────────────────────────────────────────────────
#
# Create the token at https://dash.cloudflare.com/profile/api-tokens with the
# scopes ../cloudflare/versions.tf lists (Zone:Read, Zone Settings:Edit, Cache
# Rules:Edit, Zone WAF:Edit, Bot Management:Edit, Cache Purge), then:
#
#   aws ssm put-parameter --profile admin --region us-east-1 \
#     --name /shared/prod/cloudflare/api-token \
#     --type SecureString --overwrite \
#     --value "$CLOUDFLARE_API_TOKEN"
#
# Read it back the way the edge stack should:
#
#   export CLOUDFLARE_API_TOKEN="$(aws ssm get-parameter --profile cloudflare-edge \
#     --region us-east-1 --name /shared/prod/cloudflare/api-token \
#     --with-decryption --query Parameter.Value --output text)"
#
# NEVER pass the token on a command line in a shared shell — it lands in history.
# The `put-parameter` above reads it from the environment for that reason.
###############################################################################

resource "aws_ssm_parameter" "cloudflare_api_token" {
  name        = "/shared/${var.env}/cloudflare/api-token"
  description = "Cloudflare API token for the ../cloudflare edge stack. Account-wide bearer credential — can repoint DNS for every domain. Value is set OUT OF BAND; Terraform never holds it."
  type        = "SecureString"
  tier        = "Standard"

  # A placeholder, written exactly once. If this string is ever what comes back
  # from a `get-parameter`, the real token was never put in — which is a much
  # better failure than a plausible-looking wrong value, because it says so.
  value = "PLACEHOLDER-set-out-of-band-see-06-cloudflare-token.tf"

  lifecycle {
    # THE LOAD-BEARING LINE. Without it the next apply would overwrite a live
    # token with the placeholder above and take the edge stack down until
    # somebody worked out why.
    ignore_changes = [value]
  }

  tags = {
    Rotation = "manual"
    Scope    = "cloudflare-account-wide"
  }
}

###############################################################################
# The role that reads it.
#
# NOT `agent`. That role is an authoxi allowlist — its SSM grant is scoped to
# `parameter/authoxi/*` and its state grant to `authoxi/*`, both deliberately.
# Widening it to reach a shared, account-wide credential would undo the property
# that makes it worth having.
#
# NOT `AdministratorAccess` either, which is what the edge stack is applied as
# today. Administrator is the identity that can do everything; using it to run
# one stack that needs one token and one state prefix is the habit this account
# has been moving away from since root was removed.
#
# So: a third role, scoped to exactly the two things the edge stack touches —
# its own state prefix and its own token. It can reach no AWS resource that
# Cloudflare does not configure, which is the whole point: the blast radius of
# this role is Cloudflare, and the blast radius of the Cloudflare token is
# already Cloudflare. The role adds no new exposure; it removes the AWS-side
# exposure that came from applying the stack as an administrator.
###############################################################################

data "aws_iam_policy_document" "cloudflare_edge_assume" {
  # The SAME trust shape as `agent`, and reusing its variable rather than
  # retyping the pattern: an ArnLike match on the Identity Center
  # AdministratorAccess role, which survives the permission set being recreated
  # (its trailing hex is regenerated each time).
  #
  # NOT an MFA condition. The first draft of this file had one, on the reasoning
  # that assuming a production role should be deliberate — but Identity Center
  # sessions do not reliably carry `aws:MultiFactorAuthPresent`, so it would have
  # made the role unassumable and the failure reads as a trust-policy mystery
  # rather than a missing condition key. The MFA requirement belongs on the
  # Identity Center sign-in, where it applies once and actually holds.
  #
  # There is no OIDC trust here yet on purpose: nothing runs this stack
  # unattended, and a trust policy for a workflow that does not exist is a door
  # with no building behind it. Add it when a workflow needs it, as a SECOND
  # statement pinned to `environment:<name>` with StringEquals — never a
  # `repo:owner/repo:*` wildcard, which any branch can satisfy.
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

resource "aws_iam_role" "cloudflare_edge" {
  name                 = "cloudflare-edge"
  description          = "Applies personal/infra/cloudflare. Reads the Cloudflare token and its own tfstate prefix. Nothing else."
  assume_role_policy   = data.aws_iam_policy_document.cloudflare_edge_assume.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "cloudflare_edge" {
  # ── The token, read-only ───────────────────────────────────────────────────
  # Read, not write. Rotation is a deliberate act performed as an administrator;
  # a role that can overwrite the credential it authenticates with can lock
  # itself — and everything else — out of the edge.
  statement {
    sid       = "ReadCloudflareToken"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:${local.region}:${local.acct}:parameter/shared/${var.env}/cloudflare/api-token"]
  }

  # SecureString means KMS. Without this the GetParameter above returns
  # AccessDeniedException naming KMS, not SSM, which reads like the wrong
  # problem entirely.
  #
  # `resources = ["*"]` WITH the ViaService condition, which is the same shape
  # `05-agent-role.tf` uses and is not laziness. An IAM policy cannot name a KMS
  # ALIAS in Resource — aliases are not valid there and the statement would
  # simply never match — and the AWS-managed `aws/ssm` key has no stable ARN to
  # write down. The condition is what constrains this: the right can only be
  # spent through SSM, so it cannot be turned against anything else in the
  # account that happens to be KMS-encrypted. (My first draft used the alias ARN.
  # It validated, and it would have failed at runtime with a denial that looked
  # like a missing grant rather than an unmatchable one.)
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

  # ── Its own Terraform state, and nothing else in that bucket ───────────────
  # The same prefix-scoping `agent` gets, for the same reason: this bucket also
  # holds `shared/terraform.tfstate` (the RDS master password, in plaintext) and
  # `existing/terraform.tfstate` (a decade of other production). A bucket-level
  # grant would hand both over without touching IAM.
  statement {
    sid       = "TfStateCloudflarePrefixOnly"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.tfstate_bucket}/cloudflare/*"]
  }

  statement {
    sid       = "TfStateListScoped"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.tfstate_bucket}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["cloudflare/*"]
    }
  }

  # ── Explicit denies: defence in depth, not the boundary ────────────────────
  # The allowlist above already excludes these. They are named anyway because
  # `05-agent-role.tf` records why (F10): a deny written only against the
  # threats you happen to remember is exactly the failure mode an allowlist
  # exists to prevent — so the two named state files that would be most costly
  # to leak get said out loud.
  statement {
    sid     = "DenyOtherTfState"
    effect  = "Deny"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "arn:aws:s3:::${local.tfstate_bucket}/shared/*",
      "arn:aws:s3:::${local.tfstate_bucket}/existing/*",
      "arn:aws:s3:::${local.tfstate_bucket}/authoxi/*",
      "arn:aws:s3:::${local.tfstate_bucket}/agitome/*",
    ]
  }

  # The shared RDS master password lives one path away from the token. Nothing
  # in the allowlist reaches it; this makes that permanent rather than incidental.
  statement {
    sid       = "DenySharedRdsMasterPassword"
    effect    = "Deny"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:${local.region}:${local.acct}:parameter/shared/${var.env}/rds/master-password"]
  }
}

resource "aws_iam_role_policy" "cloudflare_edge" {
  name   = "cloudflare-edge"
  role   = aws_iam_role.cloudflare_edge.id
  policy = data.aws_iam_policy_document.cloudflare_edge.json
}

output "cloudflare_token_parameter" {
  description = "Where the Cloudflare API token lives. The VALUE is set out of band — see the header of 06-cloudflare-token.tf."
  value       = aws_ssm_parameter.cloudflare_api_token.name
}

output "cloudflare_edge_role_arn" {
  description = "Assume this to run the ../cloudflare stack. Not `agent` (authoxi-scoped), not AdministratorAccess."
  value       = aws_iam_role.cloudflare_edge.arn
}
