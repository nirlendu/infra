# personal/infra/existing — the imported live-account replica

Terraform tracking the **pre-existing, kept** AWS resources so nothing on the
account is orphan/untracked. Imported from live (not created by TF) via
`import {}` blocks + `terraform plan -generate-config-out`. **`terraform plan`
is clean (zero drift).**

State: remote — `s3://nirlendu-tfstate-419105693501/existing/terraform.tfstate`
(versioned, encrypted, native S3 locking).

## What's tracked (63 resources)
| Type | Count | File |
|---|---|---|
| `aws_acm_certificate` | 10 | `generated_acm.tf` |
| `aws_cloudfront_distribution` | 25 | `generated_cloudfront.tf` |
| `aws_s3_bucket` | 28 | `generated_s3.tf` |

Buckets span 3 regions (23 ap-south-1, 1 us-east-1, 4 us-west-2) via the
aliased providers in `versions.tf`.

## Scope notes
- **Bootstrap exception:** the state bucket `nirlendu-tfstate-419105693501` is
  intentionally NOT imported (it stores the state that would manage it).
- **Bucket-level tracking:** `aws_s3_bucket` (existence + core) is in state. The
  per-bucket sub-configs (website / policy / lifecycle / CORS) are not separately
  declared — so they produce no drift, but if you want them codified too, add
  `aws_s3_bucket_website_configuration` etc. import blocks per bucket.
- `generated_*.tf` are Terraform's auto-generated configs — reviewed, plan-clean.
  Tidy/rename as desired.

## Sibling stacks
`../terraform` = greenfield **shared-infra** (VPC + Postgres + budgets + SNS +
SSM) for NEW apps (authoxi, etc.). Separate state, **applied** (57 resources as
of 2026-09-02 — the "not yet applied" note here was stale). This `existing/`
stack is only the legacy live footprint we kept.

`../cloudflare` = the **edge** stack (cache rules, rate limiting, bot
protection). Relevant here because every distribution in `generated_cloudfront.tf`
sits behind Cloudflare, so Cloudflare's cache — not CloudFront's — determines
what these distributions actually cost.
