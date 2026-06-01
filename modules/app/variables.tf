###############################################################################
# Reusable per-app infra module — inputs.
#
# Owns the GENERIC AWS footprint every app on the shared stack needs: a host SG
# (+ ingress to the shared RDS SG), an instance role, a backup bucket, the EC2
# host (+ EBS data volume, EIP, auto-recovery, DLM snapshots), a per-app budget
# + behaviour alarms, and the per-app Postgres role/db SSM params.
#
# App-SPECIFIC things are passed in: the bootstrap script (user_data_path) and
# the list of app secret names to generate (app_secret_keys). Everything else
# is parametrised by name_prefix.
###############################################################################

variable "name_prefix" {
  description = "App name. Drives every resource name and the SSM path /<name_prefix>/<env>/*."
  type        = string
}

variable "env" {
  description = "App environment (prod / staging). Part of the resource name prefix."
  type        = string
  default     = "prod"
}

variable "shared_env" {
  description = "Environment of the shared-infra stack to consume (usually == env)."
  type        = string
  default     = "prod"
}

variable "alert_email" {
  description = "Where per-app budget alerts go + the email Caddy registers with Let's Encrypt."
  type        = string
}

variable "app_budget_usd" {
  description = "Monthly spend ceiling for resources tagged Project=<name_prefix>."
  type        = number
  default     = 40
}

# ───── compute / data ─────

variable "instance_type" {
  description = "EC2 instance class. Default t4g.small (2 vCPU / 2 GB ARM) — bump per app via the root."
  type        = string
  default     = "t4g.small"
}

variable "data_volume_size_gb" {
  description = "Detachable EBS data volume size."
  type        = number
  default     = 20
}

variable "snapshot_retention_days" {
  description = "DLM daily snapshot retention. 3 days is the cheap floor."
  type        = number
  default     = 3
}

variable "data_mount" {
  description = "Where the EBS data volume mounts. Empty → /var/lib/<name_prefix>."
  type        = string
  default     = ""
}

# ───── network / access ─────

variable "ssh_cidr" {
  description = "CIDR allowed to reach port 22. Empty disables SSH (operator uses SSM)."
  type        = string
  default     = ""
}

variable "domain" {
  description = "Optional public domain. When set, Caddy obtains a Let's Encrypt cert."
  type        = string
  default     = ""
}

# ───── source pins ─────

variable "git_repo_url" {
  description = "Repo the host clones at first boot."
  type        = string
}

variable "git_ref" {
  description = "Git ref (branch / tag) to deploy."
  type        = string
  default     = "main"
}

# ───── bootstrap + secrets ─────

variable "user_data_path" {
  description = "Path to the app's first-boot bootstrap template. The module renders it with templatefile() and injects the standard vars (region, name_prefix, env, shared_env, git_repo_url, git_ref, domain, caddy_email, backup_bucket, data_mount) merged with user_data_vars."
  type        = string
}

variable "user_data_vars" {
  description = "Extra template variables merged into the bootstrap render (app-specific knobs)."
  type        = map(string)
  default     = {}
}

variable "app_secret_keys" {
  description = "SSM SecureString names to generate (a random 48-char value each), stored at /<name_prefix>/<env>/<KEY>. e.g. [\"AGENTLOX_INGEST_API_KEY\"]. The host reads them by name at boot."
  type        = list(string)
  default     = []
}
