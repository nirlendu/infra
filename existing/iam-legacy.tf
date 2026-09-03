###############################################################################
# Legacy IAM users — remove the privilege, keep the credential working.
#
# THE PROBLEM
#
# Two IAM users predate this account's move to SSO. Between them they hold two
# access keys created in 2020, and one of those keys has its SECRET committed in
# plaintext at geniusjnr/backend/package.json line 18, in git since 2022-05-03,
# still in HEAD, in a repo with no CI that could ever have scanned it.
#
# Both users reach AdministratorAccess. So does that committed credential.
#
# WHY NOT JUST DELETE THE KEY
#
# Because `aws_iam_access_key` cannot be imported — the provider has never
# supported it — so a pre-existing key cannot be brought under Terraform and
# flipped to Inactive. The only Terraform-native route to deleting the key is
# deleting the USER (`aws_iam_user` does import, and `force_destroy` takes its
# keys with it), and that would break geniusjnr/practise-web, the one legacy
# pipeline still deploying successfully (last green run 2026-08-31).
#
# The standing instruction is not to touch the legacy apps until they are
# retired. So this file does the other thing, which turns out to be better:
#
#   the danger is not that a key exists. It is that the key is Administrator.
#
# Take the privilege away and the credential in git history becomes a write
# token for one static-site bucket. Nothing in any legacy repo changes, no
# secret is rotated, no workflow is edited, and practise-web keeps deploying.
#
# WHAT practise-web ACTUALLY NEEDS — read from its workflow, not assumed:
#
#   aws s3 sync out/ s3://web.geniusjnr.com.production --exclude ...
#   aws cloudfront create-invalidation --distribution-id E9834VVALEIQC
#
# That is all. No IAM, no EC2, no RDS, and no Lambda — checked: this account
# has ZERO Lambda functions in us-east-1 and ap-south-1, so the `serverless
# deploy` script that shares this credential deploys to nothing and loses
# nothing by having Lambda permissions withdrawn.
#
# ─────────────────────────────────────────────────────────────────────────────
# THIS FILE APPLIES IN TWO PHASES. THE ORDER IS THE SAFETY PROPERTY.
#
#   PHASE 1 (this file as committed) is PURELY ADDITIVE. It creates the scoped
#     policy, attaches it, attaches the cost guardrails, and brings the existing
#     admin grants under Terraform management. Nobody loses a permission. After
#     this apply the user has admin AND the scoped policy — deliberately, so the
#     replacement is proven in place before the original is removed.
#
#   PHASE 2 is a second commit that deletes the two clearly-marked blocks at the
#     bottom of this file and empties the group membership. THAT apply is the
#     one that removes admin.
#
# Doing it in one step would create a window where the attachment is destroyed
# before its replacement exists, and the window would land on a live deploy.
# ─────────────────────────────────────────────────────────────────────────────
###############################################################################

data "aws_caller_identity" "current" {}

# Owned by ../terraform. Looked up rather than hardcoded so a policy rebuild
# does not leave a dangling ARN here.
data "aws_iam_policy" "cost_guardrails" {
  name = "shared-prod-cost-guardrails"
}

locals {
  legacy_admin_user  = "nirlendu@gmail.com"
  legacy_unused_user = "dailyappco@gmail.com"

  # The single bucket and single distribution practise-web touches.
  legacy_deploy_bucket       = "web.geniusjnr.com.production"
  legacy_deploy_distribution = "E9834VVALEIQC"
}

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 1a — the replacement policy.
#
# Written to the measured need and nothing wider. If a legacy pipeline is ever
# revived and needs another bucket, add that bucket here explicitly; do not
# reach for AmazonS3FullAccess again.
#
# NOTE FOR ANYONE TEMPTED TO WIDEN THIS: the credential this policy governs is
# in a git repository in plaintext and cannot be un-published. Its blast radius
# is exactly this document. That is the entire security property.
# ══════════════════════════════════════════════════════════════════════════════
resource "aws_iam_policy" "legacy_web_deploy" {
  name        = "legacy-web-deploy"
  description = "Least-privilege replacement for AdministratorAccess on the 2020-era legacy deploy user. See iam-legacy.tf — this credential is public in git history and must never be widened."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListTheOneBucket"
        Effect = "Allow"
        Action = ["s3:ListBucket", "s3:GetBucketLocation"]
        # s3 sync lists before it writes; without GetBucketLocation the CLI
        # cannot resolve the ap-south-1 endpoint and fails with a 301 that
        # reads like a missing bucket.
        Resource = ["arn:aws:s3:::${local.legacy_deploy_bucket}"]
      },
      {
        Sid    = "WriteTheOneBucket"
        Effect = "Allow"
        # DeleteObject is required: `s3 sync` prunes. It is scoped to this one
        # bucket's contents and cannot reach the bucket itself.
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = ["arn:aws:s3:::${local.legacy_deploy_bucket}/*"]
      },
      {
        Sid    = "InvalidateTheOneDistribution"
        Effect = "Allow"
        # GetInvalidation lets the CLI poll for completion; CreateInvalidation
        # alone makes `--wait` style flows fail confusingly.
        Action   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
        Resource = ["arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${local.legacy_deploy_distribution}"]
      },
    ]
  })

  tags = {
    Project   = "shared"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_user_policy_attachment" "legacy_web_deploy" {
  user       = local.legacy_admin_user
  policy_arn = aws_iam_policy.legacy_web_deploy.arn
}

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 1b — make the cost guardrails bind, for the first time.
#
# `shared-prod-cost-guardrails` is an explicit-Deny policy that blocks NAT
# gateways, load balancers, oversized instances and Multi-AZ RDS. It has existed
# since July and is attached to a group with ZERO members — so it has never
# constrained anything.
#
# An explicit Deny beats any Allow, including AdministratorAccess. That means
# this attachment takes effect in PHASE 1, before admin is removed: from the
# first apply, the credential sitting in git cannot provision the expensive
# resources even while it is still nominally an administrator.
#
# It is attached to both users, including the one whose key has never been used
# — an unused credential is exactly the one nobody would notice being used.
# ══════════════════════════════════════════════════════════════════════════════
resource "aws_iam_user_policy_attachment" "legacy_cost_guardrails" {
  for_each = toset([local.legacy_admin_user, local.legacy_unused_user])

  user       = each.value
  policy_arn = data.aws_iam_policy.cost_guardrails.arn
}

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 1c — adopt the existing admin grants so Terraform can later remove them.
#
# These import blocks bring the CURRENT state under management. They change
# nothing on their own: after this apply the grants exist exactly as before, but
# Terraform knows about them, which is the prerequisite for deleting them
# without an out-of-band API call.
#
# Import IDs: aws_iam_user_policy_attachment is "<user-name>/<policy-arn>".
# ══════════════════════════════════════════════════════════════════════════════

import {
  to = aws_iam_user_policy_attachment.legacy_admin_access
  id = "nirlendu@gmail.com/arn:aws:iam::aws:policy/AdministratorAccess"
}

import {
  to = aws_iam_user_policy_attachment.legacy_s3_full_access
  id = "nirlendu@gmail.com/arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# The group is the SECOND path to admin and is easy to miss: removing the two
# direct attachments above while leaving group membership in place would look
# like a successful de-privileging and change nothing at all. `admin-all` has
# AdministratorAccess attached and contains exactly these two users.
#
# aws_iam_user_group_membership, NOT aws_iam_group_membership: the latter is
# what this file reached for first and it cannot be imported at all — the
# provider rejects it with "resource aws_iam_group_membership doesn't support
# import", which would have meant either an out-of-band API call or letting
# Terraform take exclusive ownership of a group's membership sight-unseen.
#
# The per-user resource imports cleanly as "<user-name>/<group-name>" and is
# non-exclusive, so it manages only this user's membership of this group and
# cannot silently evict anyone else who is added to the group later.
import {
  to = aws_iam_user_group_membership.legacy_admin_group["nirlendu@gmail.com"]
  id = "nirlendu@gmail.com/admin-all"
}

import {
  to = aws_iam_user_group_membership.legacy_admin_group["dailyappco@gmail.com"]
  id = "dailyappco@gmail.com/admin-all"
}

# ══════════════════════════════════════════════════════════════════════════════
# ▼▼▼ PHASE 2 — DELETE EVERYTHING BETWEEN THESE MARKERS TO DE-PRIVILEGE ▼▼▼
#
# Deleting these three resources (and their import blocks above) makes the next
# apply destroy the grants, which is the actual privilege removal. Do it in its
# own commit, after phase 1 has applied cleanly, so the plan for that step
# contains nothing but these removals and is trivial to read.
#
# ALL THREE MUST GO TOGETHER. Removing the two direct attachments while leaving
# the group membership looks like success and changes nothing — the group
# carries AdministratorAccess too.
#
# VERIFY AFTER APPLYING PHASE 2: re-run the geniusjnr/practise-web workflow. It
# is the only consumer that must still work. If it fails, the failure will name
# the missing action and it belongs in aws_iam_policy.legacy_web_deploy above.
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_user_policy_attachment" "legacy_admin_access" {
  user       = local.legacy_admin_user
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_user_policy_attachment" "legacy_s3_full_access" {
  user       = local.legacy_admin_user
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_user_group_membership" "legacy_admin_group" {
  for_each = toset([local.legacy_admin_user, local.legacy_unused_user])

  user   = each.value
  groups = ["admin-all"]
}

# ▲▲▲ END PHASE 2 BLOCK ▲▲▲
#
# RESIDUAL RISK, recorded rather than quietly carried: both users keep console
# login profiles created in 2020 with ZERO MFA devices. `aws_iam_user_login_profile`
# cannot be imported either (same provider limitation as access keys), so this
# cannot be closed here without deleting the users. After phase 2 a console
# login on these users reaches one S3 bucket and one invalidation, which is the
# same blast radius as the key. It closes fully when the legacy estate is retired.
