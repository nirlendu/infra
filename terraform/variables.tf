variable "aws_region" {
  description = "Region for the shared VPC + RDS. Pick once — every app stack will deploy here."
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Environment tag (prod / staging). Shared infra usually has one of each."
  type        = string
  default     = "prod"
}

variable "availability_zone" {
  description = "Primary AZ. Single-AZ for cost; RDS still needs a 2nd AZ for its subnet group."
  type        = string
  default     = "us-east-1a"
}

# ───── budget guardrails (account-wide) ─────
#
# Conservative defaults sized for: shared-infra (~$29) + 1 app (~$34) = ~$63
# steady state. If you add apps, raise these — but don't raise them silently.
# Every threshold here is intentionally low so a surprise gets caught early.

variable "alert_email" {
  description = "Email to receive every budget / billing / anomaly alert."
  type        = string
}

variable "monthly_budget_usd" {
  description = <<-EOT
    Total monthly AWS spend ceiling — the catch-all beneath every per-service
    budget, and the only one that sees spend on a service nobody thought to name.

    Raised 80 -> 110 for uni. Measured steady state after it lands: RDS $26 +
    ECS $16.50 (three tasks, Spot) + S3 $11 + IPv4 $9.25 + Route 53 $1 + a
    CloudFront line that should settle near its June figure. That is ~$75, and an
    80% forecast alert on $80 would have fired on arrival — which is how a
    genuine ceiling becomes noise people filter.

    This is the number to revisit when a product is added, not the per-service
    ones. It should sit close enough to reality to mean something.
  EOT
  type        = number
  default     = 110
}

variable "daily_anomaly_usd" {
  description = "Daily-spend tripwire across the whole account. Steady state is ~$2/day, so $4 fires on ~2x normal — catches NAT Gateway ($1.10/day idle) immediately."
  type        = number
  default     = 4
}

variable "billing_alarm_usd" {
  description = "Hard CloudWatch billing alarm. Redundant belt-and-braces with Budgets."
  type        = number
  default     = 120
}

variable "anomaly_threshold_usd" {
  description = "Per-service Cost Anomaly Detector alert threshold. $3 = the smallest impact AWS treats as an anomaly."
  type        = number
  default     = 3
}

# ───── per-service budget caps (free tier of Budgets is 62 budget-days/mo;
# beyond that it's $0.02/budget/day. We accept ~$3/mo to cover service-level
# tripwires that fire BEFORE the monthly total budget). ─────

variable "ec2_budget_usd" {
  description = "Cap on monthly EC2 spend. Default $40 ≈ 1 t4g.medium with IPv4. If you add a second host, bump this."
  type        = number
  default     = 40
}

variable "rds_budget_usd" {
  description = "Cap on monthly RDS spend. Default $32 ≈ db.t4g.small + 20 GB storage."
  type        = number
  default     = 32
}

variable "vpc_budget_usd" {
  description = <<-EOT
    Cap on monthly VPC spend — public IPv4 addresses, in practice.

    Was $1 as a NAT anti-budget, which stopped working the moment AWS began
    billing in-use public IPv4 at $0.005/hr under this same service. Each Fargate
    task with a public IP is ~$3.08/mo, so two tasks held it permanently at $6.08
    against a $1 limit and it could no longer detect anything.

    $15 covers four tasks with headroom. NAT now has its own anti-budget filtered
    on usage type, where $1 is genuinely zero.
  EOT
  type        = number
  default     = 15
}

variable "s3_budget_usd" {
  description = <<-EOT
    Cap on monthly S3 spend. $11.01 / $10.73 / $11.16 across Jun-Aug — the only
    flat line in the account, third largest, and it had no budget at all.

    $20 rather than $12 because the documents bucket starts growing with real
    uploads shortly, and a budget that fires on expected growth is one people
    learn to dismiss.
  EOT
  type        = number
  default     = 20
}

variable "elb_budget_usd" {
  description = "Cap on monthly Elastic Load Balancing spend. Default $1 — anything above zero means an ALB/NLB exists, which we never want."
  type        = number
  default     = 1
}

variable "data_transfer_budget_usd" {
  description = "Cap on monthly data-transfer-out cost for the 'AWS Data Transfer' service line (EC2/inter-region/S3). Default $5 = ~55 GB egress beyond the 100 GB free tier. NOTE: this does NOT cover CloudFront egress — see cloudfront_budget_usd."
  type        = number
  default     = 5
}

variable "cloudfront_budget_usd" {
  description = <<-EOT
    Cap on monthly CloudFront spend (egress + requests).

    CloudFront bills under its own service line, NOT 'AWS Data Transfer' — the
    gap that let a $171 bot-traffic bill through undetected in Aug 2026.

    LOWERED 15 -> 5 on 2026-09-03. The old $15 was set as "3x a normal month",
    which is the right way to size a budget for a service you expect to spend
    money on. CloudFront is not one: correct spend here is $0, because the
    always-free tier (1 TB + 10M requests) is far above anything this account
    legitimately serves — the three live products moved 0.2 GB in August
    between them. A threshold set against normal cannot distinguish "quiet" from
    "about to fall off the free-tier cliff"; a threshold set against ZERO can.

    This is now the SECOND line of defence rather than the first. The usage
    budgets in 07-usage-budgets.tf fire on GB and requests while cost is still
    $0.00, which is weeks earlier. By the time this one fires, the cliff has
    already been crossed and the question is how far.
  EOT
  type        = number
  default     = 5
}

variable "ecs_budget_usd" {
  description = "Cap on monthly ECS/Fargate spend. Default $25 ≈ 2x one 0.25 vCPU / 1 GB ARM task + its public IPv4. This budget is the ONLY guardrail on Fargate task size/count — IAM has no condition key for either."
  type        = number
  default     = 25
}

# ───── RDS sizing ─────

variable "rds_instance_class" {
  description = "Shared Postgres instance class. db.t4g.small gives 2GB RAM ≈ comfortable headroom for 3–5 small apps."
  type        = string
  default     = "db.t4g.small"
}

variable "rds_engine_version" {
  description = <<-EOT
    Postgres MAJOR version. Deliberately not a minor.

    This was pinned to "16.12" to match the app's docker-compose image. That pin
    could never hold: `auto_minor_version_upgrade = true` is set below, so AWS
    moves the minor whenever it likes — it moved to 16.13 — and Terraform then
    plans a DOWNGRADE, which RDS refuses. The stack could not apply at all until
    this changed, which also blocked the unrelated CloudFront budget sharing it.

    A major-only value is what the provider wants when auto-minor-upgrade is on:
    it matches any 16.x, so AWS patching stops being drift. Determinism was never
    actually on offer here — the choice was between a pin that reflects reality
    and one that fights it.

    Matching the local docker-compose minor was the original justification and it
    does not survive scrutiny: a dev container and a managed instance have no
    reason to share a patch level, and Postgres does not break compatibility
    across them.

    Bump this only for a MAJOR upgrade (16 -> 17), which is a deliberate,
    downtime-carrying operation and needs `allow_major_version_upgrade`.
  EOT
  type        = string
  default     = "16"
}

variable "rds_storage_gb" {
  description = "Allocated storage for shared RDS."
  type        = number
  default     = 20
}

variable "rds_storage_max_gb" {
  description = "Storage autoscale ceiling (a hard cap so a runaway app cannot 10x your bill). Set equal to rds_storage_gb to disable autoscale."
  type        = number
  default     = 50
}

variable "rds_backup_retention_days" {
  description = <<-EOT
    RDS automated backup retention, in days.

    Raised 7 -> 14. Backup storage up to the instance's allocated storage is free,
    and the measured position is 2.9 GB of data against a 20 GB allocation with
    `TotalBackupStorageBilled` reading 0.00 — so doubling the window costs nothing
    and is very likely to stay free.

    Seven days is the wrong number for the failure that actually loses data.
    Hardware failure is caught in minutes; logical corruption — a bad migration, a
    delete with a wrong WHERE — is often noticed a week or more later, which is
    exactly when a 7-day window has just closed.

    This covers the INSTANCE. On a shared instance it does not cover a product:
    point-in-time recovery restores every database at once, so recovering uni
    alone still needs its own logical dump. See the pg_dump job in the app stacks.
  EOT
  type        = number
  default     = 14
}

# ───── Usage budgets (07-usage-budgets.tf) ─────
#
# These are USAGE limits, not dollars. They exist because dollars are blind
# below a free tier — see the header of 07-usage-budgets.tf for the July 2026
# case where every cost budget correctly read $0.00 for a month while the crawl
# that produced August's $172 was already running.
#
# Set to HALF the free tier so the first notification (at 40%) lands at roughly
# 20% of free-tier consumption.

variable "cloudfront_egress_gb_limit" {
  description = <<-EOT
    CloudFront egress budget in GB. Default 500 = half the 1,024 GB always-free
    tier, so the 40% notification fires at ~200 GB — about four days into a crawl
    at August 2026 rates, rather than the three weeks it actually took.

    Correct steady-state value for this account is single-digit GB: the three
    live products together moved 0.2 GB in August. Do not raise this to
    accommodate traffic without first establishing that the traffic is wanted.
  EOT
  type        = number
  default     = 500
}

variable "cloudfront_requests_limit" {
  description = <<-EOT
    CloudFront request budget. Default 5,000,000 = half the 10M always-free
    tier.

    This is the more sensitive of the two CloudFront tripwires for this account:
    August crossed 10M requests around the 9th but did not cross 1 TB of egress
    until the 20th. Requests lead, bytes follow.
  EOT
  type        = number
  default     = 5000000
}

variable "s3_requests_limit" {
  description = <<-EOT
    S3 standard API request budget. Default 3,000,000.

    August recorded roughly 11.8M GETs in ap-south-1 ($4.74 of a $11.16 S3
    bill) — the crawl reaching the buckets behind CloudFront. Normal for this
    account is deploys and nothing else, which is thousands, not millions.
  EOT
  type        = number
  default     = 3000000
}

# ───── Circuit breaker (09-circuit-breaker.tf) ─────

variable "breaker_armed" {
  description = <<-EOT
    Whether the cost circuit breaker actually disables a distribution, or only
    logs what it would have done.

    Default TRUE, deliberately. An unarmed breaker is a breaker that will be
    found unarmed during the incident it was built for — and the containment
    that makes arming safe is the allowlist below, not this flag. Set to false
    only to observe the wiring on a first apply, and set it back.
  EOT
  type        = bool
  default     = true
}

variable "breaker_allowed_distributions" {
  description = <<-EOT
    The ONLY CloudFront distributions the breaker may disable. This is the
    safety property that lets the breaker be armed by default.

    Every entry is an abandoned or dormant site. The three live products —
    authoxi (E16HT1MC29JOA9, E375MDZN4Q6T7), agitome (E3FT34HVZMITC6) and uni
    (E2QYIQKDHUWS4J) — are deliberately ABSENT, so a false positive can take a
    dead marketing site offline and can never take production offline.

    Adding a live product here converts this from a cost control into an
    availability risk. Do not.

      ETX7NAHEKHMR  code.maxinterview.com   40.1M requests / 529 GB in Aug 2026
      EGE1BE7J30U8P maxinterview.com        19.5M requests / 1,559 GB
      E3DREC6GKO0ZHN supertravelr.com        8.0M requests / 131 GB
      E9834VVALEIQC geniusjnr.com           1.0M requests / 81 GB
      E24BJHZNQCQO33 trips.supertravelr.com  0.3M requests / 4 GB

    NOTE: geniusjnr.com and supertravelr.com are "active" zones rather than
    abandoned ones, but neither has users today and both were significant
    contributors to the August bill. If either grows real traffic, remove it
    from this list at that point.
  EOT
  type        = list(string)
  default = [
    "ETX7NAHEKHMR",
    "EGE1BE7J30U8P",
    "E3DREC6GKO0ZHN",
    "E9834VVALEIQC",
    "E24BJHZNQCQO33",
  ]
}

variable "alert_sms_number" {
  description = <<-EOT
    E.164 phone number for SNS SMS alerts, e.g. "+919876543210". Empty disables
    the subscription.

    The August post-mortem's standing open item: "one Gmail inbox is not a
    control surface". SMS is billed per message (fractions of a cent) and the
    topic is low-volume by design.
  EOT
  type        = string
  default     = ""
}

# ───── VPC ─────

variable "vpc_cidr" {
  description = "CIDR for the shared VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Shared public subnet — all app EC2 hosts land here."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_a_cidr" {
  description = "Private subnet (primary AZ) — RDS subnet group."
  type        = string
  default     = "10.0.10.0/24"
}

variable "private_subnet_b_cidr" {
  description = "Private subnet (secondary AZ) — RDS subnet group needs 2 AZs even for single-AZ deploy."
  type        = string
  default     = "10.0.11.0/24"
}
