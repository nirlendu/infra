# modules/app — reusable per-app stack

The generic AWS footprint every app on the shared stack needs, so a new product
inherits it instead of re-authoring ~870 lines of Terraform. Extracted from
agentlox's `infra/terraform/`.

## What it owns (generic, parametrised by `name_prefix`)

- **Host SG** in the shared public subnet + an ingress rule on the shared RDS SG.
- **Instance role** — SSM Session Manager, read `/<name_prefix>/<env>/*` + `/shared/<env>/*`, R/W the backup bucket, a tight cost-audit read-only allow-list.
- **Backup S3 bucket** — private, versioned, encrypted, lifecycle → Glacier IR → expire.
- **EC2 host** + EBS data volume (`prevent_destroy`) + Elastic IP + auto-recovery alarms + DLM daily snapshots.
- **Per-app cost controls** — tag-filtered budget (`Project=<name_prefix>`) + NetworkOut / CPU / EBS-write alarms.
- **Per-app Postgres coordinates** in SSM — `APP_DB_PASSWORD` / `APP_DB_NAME` / `APP_DB_USER` / `BACKUP_BUCKET` (the host CREATEs the role+db on the shared RDS at first boot).

## What you pass in (app-specific)

- `user_data_path` — your repo's first-boot bootstrap template. The module renders it with `templatefile()` injecting: `aws_region, name_prefix, env, shared_env, git_repo_url, git_ref, domain, caddy_email, backup_bucket, data_mount` (merge extra knobs via `user_data_vars`).
- `app_secret_keys` — SSM SecureString names to generate a random value for (e.g. `["AGENTLOX_INGEST_API_KEY"]`, `["AUTHOXI_SECRET_KEY","AUTHOXI_MASTER_KEY"]`).
- `name_prefix`, `alert_email`, `git_repo_url`, plus optional `instance_type`, `data_volume_size_gb`, `domain`, `ssh_cidr`, `app_budget_usd`, `data_mount`.

## Prerequisite

`personal/infra/terraform/` (shared-infra) must be applied first — the module reads
the VPC / subnet / RDS / SNS coordinates from `/shared/<env>/*` in SSM.

## Usage

```hcl
provider "aws" {
  region = "us-east-1"
  default_tags { tags = { Project = "authoxi", Env = "prod", ManagedBy = "terraform" } }
}

module "app" {
  source          = "../../../../personal/infra/modules/app"
  name_prefix     = "authoxi"
  alert_email     = var.alert_email
  git_repo_url    = "https://github.com/aeternm/authoxi.git"
  instance_type   = "t4g.small"
  user_data_path  = abspath("${path.module}/../scripts/user-data.sh")
  app_secret_keys = ["AUTHOXI_SECRET_KEY", "AUTHOXI_MASTER_KEY"]
}
```

> `default_tags { Project = <name_prefix> }` is **required** in the root provider —
> the per-app budget filter counts resources by that tag.

See `examples/validate/` for a minimal config used to `terraform validate` the module.
Live consumers: `aeternm/authoxi/infra/terraform/` (and agentlox, pending migration).
