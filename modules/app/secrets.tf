###############################################################################
# PER-APP SECRETS + DB COORDINATES (SSM Parameter Store)
#
# Generic to every app: a Postgres role/db this app owns on the SHARED RDS
# instance (provisioned by the host at first boot using the shared master pw),
# plus the backup bucket id. App-specific secrets are generated from
# var.app_secret_keys (one random SecureString each).
###############################################################################

# Per-app Postgres role password. The host CREATEs this role + DB on first boot.
resource "random_password" "app_db_password" {
  length  = 40
  special = false
}

resource "aws_ssm_parameter" "app_db_password" {
  name        = "/${var.name_prefix}/${var.env}/APP_DB_PASSWORD"
  description = "Per-app Postgres role password for ${var.name_prefix}."
  type        = "SecureString"
  value       = random_password.app_db_password.result
  tier        = "Standard"
}

resource "aws_ssm_parameter" "app_db_name" {
  name        = "/${var.name_prefix}/${var.env}/APP_DB_NAME"
  description = "Per-app Postgres database on the shared RDS instance."
  type        = "String"
  value       = "${var.name_prefix}_${var.env}"
}

resource "aws_ssm_parameter" "app_db_user" {
  name        = "/${var.name_prefix}/${var.env}/APP_DB_USER"
  description = "Per-app Postgres role on the shared RDS instance."
  type        = "String"
  value       = "${var.name_prefix}_${var.env}"
}

resource "aws_ssm_parameter" "backup_bucket" {
  name        = "/${var.name_prefix}/${var.env}/BACKUP_BUCKET"
  description = "S3 bucket the host ships backups to."
  type        = "String"
  value       = aws_s3_bucket.backups.id
}

# ───── app-specific secrets (one random value per declared key) ─────
resource "random_password" "app_secret" {
  for_each = toset(var.app_secret_keys)
  length   = 48
  special  = false
}

resource "aws_ssm_parameter" "app_secret" {
  for_each    = toset(var.app_secret_keys)
  name        = "/${var.name_prefix}/${var.env}/${each.key}"
  description = "App secret ${each.key} for ${var.name_prefix}."
  type        = "SecureString"
  value       = random_password.app_secret[each.key].result
  tier        = "Standard"
}
