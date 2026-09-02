# AGENTS.md — working in this repo

## The one absolute rule

**Nothing in this account changes except through Terraform in this repo (or an
app's own `infra/`).**

No AWS console. No `aws <service> create|put|modify|delete`. No Cloudflare
dashboard. No `wrangler`. Not for a retention day, not for a cache rule, not for a
security-group port, not "just to unblock something".

Read-only is always fine — `describe`, `list`, `get`, `plan`. The rule is about
writes.

### Why it is absolute here specifically

This estate is a decade of accumulated production for several unrelated products
sharing one AWS account, one VPC and one Postgres instance. The code is the only
map of it. A change made outside Terraform does not just go undocumented — it
makes the map wrong, and the next `apply` either reverts it silently or fails on a
conflict nobody can explain.

It has already happened. `cloudflare/imports.tf` exists solely to codify a cache
fix applied by hand on 2026-09-02. That fix was correct and urgent; codifying it
afterwards still cost more than doing it in code would have.

### The one exception: a secret's VALUE

A password or API token must never enter Terraform state — state lives in S3 and
is readable by anyone with access to the bucket. So values are set out of band:

```sh
aws ssm put-parameter --name /shared/prod/... --type SecureString \
  --value "…" --overwrite
```

The **parameter resource is still declared in Terraform**, with
`lifecycle { ignore_changes = [value] }`. Terraform owns the resource; only the
secret inside it is set by hand. `geniusjnr/uni-backend/infra/terraform/registry.tf`
is the reference for the pattern.

### If an emergency forces a console change

Say so explicitly, then codify it — `terraform import`, or write the resource and
reconcile — before doing anything else. An undeclared emergency fix is exactly
what this rule exists to prevent.

## Stacks

| Directory | State key | Scope |
|---|---|---|
| `terraform/` | `shared/` | Account — VPC, RDS, budgets, SNS, SSM publish |
| `clusters/` | `clusters/` | Company — one ECS cluster per company |
| `cloudflare/` | `cloudflare/` | The edge — cache, rate limits, bots |
| `existing/` | `existing/` | Imported replica of the pre-existing footprint |

Apps own their own service in their own repo's `infra/` — `aeternm/authoxi/infra`
is the reference, `geniusjnr/uni-backend/infra` the second.

## Before you touch anything

1. `terraform plan` first, always, and read it. `0 to destroy` is not a formality.
2. Check for drift with `terraform plan -refresh-only` — the shared stack carries
   known drift (see below) that will surface on any apply.
3. Read `COST-GUARDRAILS.md`. NAT gateways and load balancers are IAM-denied, not
   merely discouraged, and that is deliberate.

## Known drift in `terraform/` (as of 2026-09-02)

- `engine_version` pins `16.12`; AWS auto-upgraded the instance to `16.13`.
  **RDS cannot downgrade a minor version, so an apply will fail until this is
  fixed.** `auto_minor_version_upgrade = true`, so pinning an exact minor is
  self-contradictory — pin the major (`"16"`) instead.
- `rds.force_ssl` has no `apply_method`, so the provider default `immediate`
  fights AWS's `pending-reboot`. It is a static parameter; add
  `apply_method = "pending-reboot"`.
- An unmanaged ingress rule on the RDS security group (`agitome Fargate task to
  the shared RDS`) shows in `-refresh-only`. **This one is fine** —
  `01-vpc.tf` sets `ignore_changes = [ingress]` because app stacks add their own
  rules. Do not "fix" it.
