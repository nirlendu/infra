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
  description = "Total monthly AWS spend ceiling. Default $80 ≈ 25% headroom over expected for 1 app. Raise deliberately as apps are added."
  type        = number
  default     = 80
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
  description = "Cap on monthly VPC spend. Default $1 — anything above zero means somebody created a NAT Gateway or VPC endpoint."
  type        = number
  default     = 1
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
  description = "Cap on monthly CloudFront spend (egress + requests). Default $15 ≈ 3x a normal month once the edge is caching properly. CloudFront bills under its own service line, NOT 'AWS Data Transfer' — a gap that let a $171 bot-traffic bill through undetected in Aug 2026."
  type        = number
  default     = 15
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
  description = "Postgres engine version. Pin a minor for deterministic upgrades. 16.12 matches the app's docker-compose pin (postgres:16.12-alpine); bump only when RDS retires it (16.4 was retired 2026-07)."
  type        = string
  default     = "16.12"
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
  description = "RDS automated backup retention. 7 days = free if total snapshot size <= DB size."
  type        = number
  default     = 7
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
