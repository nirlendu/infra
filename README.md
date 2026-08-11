# shared-infra/

Account-wide AWS resources every app in this account consumes:

- **Budgets, billing alarm, Cost Anomaly Detector, SNS alert topic** — account-level cost guardrails (see [`COST-GUARDRAILS.md`](COST-GUARDRAILS.md) for the full layer map; the spend-decision doctrine is the boardroom `cost-guardrails` skill).
- **Per-service budgets** — EC2, RDS, VPC, ELB, Data Transfer (anti-budgets that fire on the first day of a cost-killer service like NAT Gateway or ALB).
- **IAM cost-guardrails policy** — opt-in managed policy that DENIES the worst-offender API calls (NAT Gateway, ALB, oversized instances, Multi-AZ RDS, etc.).
- **VPC** — one shared VPC, one public subnet for app hosts, two private subnets for RDS.
- **RDS Postgres `db.t4g.small`** — shared database server. Each app provisions its own *database* + *role* inside it on first boot.

> Currently lives inside the `agentlox` repo for convenience. When a second app starts consuming this stack, lift `shared-infra/` into its own repo / Terraform state.

## What this is NOT

- Not per-app. App-specific resources (compute, S3 backups, app secrets, the edge) live in each app's own `infra/`.
- Not shared compute. Only DB + VPC are shared. Each app brings its own compute and picks its own shape — see below.
- Not shared Redis or ClickHouse. Those colocate with the app that uses them.

## Two sanctioned compute shapes

| | EC2 host | **ECS Fargate** |
|---|---|---|
| Stack | [`modules/app/`](modules/app/) — instance + EBS + EIP + user-data | the app's own `infra/` (authoxi is the reference) |
| Cost | ~$30/mo | ~$13/mo |
| Front door | Caddy on the host, CloudFront in front | API Gateway HTTP API → VPC link → Cloud Map |
| Deploy | `git pull` on the host | push an immutable image tag, `terraform apply` |
| Ops surface | a host to patch, a bootstrap script to rot | none |

**Fargate is the better default now** (added 2026-07-14, authoxi first). It is cheaper *and* has no
host to maintain, which matters most for a service left running unattended for months. The catch is
that Fargate's obvious design — an ALB in front — is both denied by the cost guardrails and ~$16/mo;
the sanctioned design routes API Gateway to a Cloud Map service instead, and needs no load balancer
and no NAT Gateway. `modules/app/` is kept for anything that genuinely needs a host (a daemon, a
persistent local disk). Read `aeternm/authoxi/infra/PLAN.md` before choosing.

## What's published for consumers

Every output is also written to SSM Parameter Store at `/shared/<env>/...` so app stacks don't need `terraform_remote_state`. See [`terraform/03-ssm-publish.tf`](terraform/03-ssm-publish.tf) for the full path list.

| Path | What |
|---|---|
| `/shared/<env>/vpc/id` | VPC id |
| `/shared/<env>/vpc/public-subnet-id` | Public subnet for app EC2 |
| `/shared/<env>/vpc/availability-zone` | Primary AZ (apps must put EBS here) |
| `/shared/<env>/rds/endpoint` | Postgres host |
| `/shared/<env>/rds/port` | Postgres port |
| `/shared/<env>/rds/sg-id` | RDS SG id — apps add ingress from their host SG |
| `/shared/<env>/rds/master-user` | master username |
| `/shared/<env>/rds/master-password` | master password (SecureString) — read by app user-data to provision its own DB+role |
| `/shared/<env>/sns/alerts-topic-arn` | SNS topic for budget/alarm emails |

## Quickstart

```bash
cd shared-infra/terraform/
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars       # set alert_email

terraform init
```

### Apply budgets first (so guardrails exist before any billable resource)

```bash
terraform apply \
  -target=aws_sns_topic.budget_alerts \
  -target=aws_sns_topic_subscription.budget_alerts_email \
  -target=aws_budgets_budget.monthly_cost \
  -target=aws_budgets_budget.daily_anomaly \
  -target=aws_cloudwatch_metric_alarm.billing \
  -target=aws_ce_anomaly_monitor.all_services \
  -target=aws_ce_anomaly_subscription.email
```

**Confirm the SNS subscription email** AWS sends you. Until you do, no alerts reach you.

### Apply the rest (VPC + RDS)

```bash
terraform apply
```

RDS provisioning takes ~8–10 minutes.

## Cost (steady state)

| Item | $/mo |
|---|---|
| RDS `db.t4g.small` single-AZ | 26.28 |
| RDS 20 GB gp3 storage + 7-day backups | 2.30 |
| VPC / IGW / SGs / route tables | 0 |
| **Cost guardrails** (5 paid Budgets above free tier, all CloudWatch alarms under 10-alarm free quota, SNS under email free tier, Anomaly Detector free) | ~3.00 |
| **Shared subtotal** | **~$32** |

The $3/mo for extra Budgets is deliberate insurance — see [`COST-GUARDRAILS.md`](COST-GUARDRAILS.md).

Per consumer app adds **~$13/mo on Fargate** (task + its public IPv4 + logs; authoxi) or **~$30/mo on
EC2** (host + EBS + EIP; agentlox) — see that app's own `infra/PLAN.md`. The reusable EC2 stack lives
in [`modules/app/`](modules/); the Fargate stack is not yet a module (one consumer — generalize it
when there's a second, not before).

## Connecting an app to this stack

Every app's `infra/terraform/` reads SSM:

```hcl
data "aws_ssm_parameter" "vpc_id"           { name = "/shared/prod/vpc/id" }
data "aws_ssm_parameter" "public_subnet_id" { name = "/shared/prod/vpc/public-subnet-id" }
data "aws_ssm_parameter" "rds_sg_id"        { name = "/shared/prod/rds/sg-id" }
# ...
```

And adds an ingress rule to the shared RDS SG:

```hcl
resource "aws_security_group_rule" "rds_from_host" {
  type                     = "ingress"
  security_group_id        = data.aws_ssm_parameter.rds_sg_id.value
  source_security_group_id = aws_security_group.host.id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  description              = "<app-name> host → shared RDS"
}
```

The app then provisions its own database + role, once, using the master password:

1. `CREATE ROLE <app>_app LOGIN PASSWORD '<per-app-pw>';`
2. `CREATE DATABASE <app>_db OWNER <app>_app;`
3. `REVOKE ALL ON DATABASE <app>_db FROM PUBLIC;`

…and connects as `<app>_app` from then on. **On EC2** that runs in user-data at first boot (see
agentlox's `infra/scripts/user-data.sh`). **On Fargate** it is a one-shot ECS task with its own
execution role (see authoxi's `app/ops/bootstrap_db.py` + `terraform output bootstrap_command`).

The Fargate split is strictly safer, and worth copying: on EC2 the long-lived host holds the
master-password grant *forever*, because user-data needed it once at boot. On Fargate only a task
that runs for four seconds can read it — the API task's role cannot. That takes the blast radius
below from "always" to "during bootstrap", for free.

## Security trade-offs

- Apps have IAM access to read `/shared/<env>/rds/master-password`. A compromised app host can reach other apps' databases. **Acceptable pre-revenue**, not acceptable at scale.
- Mitigation when you outgrow this: split RDS per environment-class (prod/staging in different shared instances), or move each app to its own RDS once it starts paying.

## Tearing down (rare)

RDS has `deletion_protection = true`. To destroy:

```bash
# 1. Remove every consumer app's stack first (each app uses this RDS).
# 2. Disable deletion protection:
terraform apply -var rds_instance_class=db.t4g.small \
                -target=aws_db_instance.shared \
                -replace=aws_db_instance.shared    # nope — instead edit 02-rds.tf to set deletion_protection=false, then:
terraform apply
terraform destroy
```
