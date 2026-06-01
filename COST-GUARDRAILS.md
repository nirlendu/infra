# Cost Guardrails — Layered Defense (account-wide)

> **Goal:** never see an unexpected AWS bill again.
> If any one mechanism here fails, the next one catches it.

This is the **account-wide** cost doctrine for the whole AWS account — owned by `personal/infra/`
(shared-infra) and consumed by every product. The judgment layer that decides *whether to spend at
all* is the boardroom `cost-guardrails` skill (`personal/boardroom/canon/skills/cost-guardrails/`);
**this doc is the mechanical map** of what's deployed to catch spend when it happens.

The plan stacks **independent detection layers** plus **prevention layers**. Each exists because any
single mechanism is insufficient on its own — Budgets emails get silently delayed, Anomaly Detector
needs a baseline, CloudWatch alarms can be muted. Layers split into **account-wide** (here, in
`personal/infra/`) and **per-app** (in each product's `infra/`, tagged by `Project=<app>`).

---

## Layer map

```
                        ┌────────────────────────────────────────┐
                        │  Prevention (block at the API call)     │
                        ├────────────────────────────────────────┤
   IAM cost-guardrails  │  P1. Deny NAT Gateway / ALB / large     │
   managed policy       │      instance types / Multi-AZ RDS /    │
   (account-wide)       │      pricey managed services            │
                        ├────────────────────────────────────────┤
   AWS Service Quotas   │  P2. Manual: lower vCPU + RDS quotas     │
                        └────────────────────────────────────────┘

                        ┌────────────────────────────────────────┐
                        │  Detection (alert if it happens)        │
                        ├────────────────────────────────────────┤
   shared-infra Budgets │  D1. Monthly total — $80 / 25-50-80% f  │
   (account-wide)       │  D2. Daily anomaly — $4/day             │
                        │  D3. EC2 service — $40                   │
                        │  D4. RDS service — $32                   │
                        │  D5. VPC anti-budget — $1 (NAT catch)    │
                        │  D6. ELB anti-budget — $1 (ALB catch)    │
                        │  D7. Data transfer — $5                  │
                        ├────────────────────────────────────────┤
   per-app Budgets      │  D8. App-tag-filtered — $40 (in infra/) │
                        ├────────────────────────────────────────┤
   CloudWatch alarms    │  D9.  EstimatedCharges → $120 ceiling   │
   (account-wide)       │  D13. RDS FreeStorageSpace < 20%        │
                        │  D14. RDS DatabaseConnections > 150     │
                        ├────────────────────────────────────────┤
   per-app alarms       │  D10. EC2 NetworkOut sustained          │
   (in each infra/)     │  D11. EC2 CPU sustained 90%             │
                        │  D12. EBS WriteOps storm                │
                        ├────────────────────────────────────────┤
   Cost Anomaly Det.    │  D15. Per-service ML baseline (free)    │
                        ├────────────────────────────────────────┤
   Weekly cost-audit    │  D16. Orphan EBS, EIPs, NAT, ELB, log   │
                        │       groups, S3 buckets, MTD spend     │
                        └────────────────────────────────────────┘
```

---

## Prevention layers

### P1. IAM cost-guardrails managed policy

A managed IAM policy (`shared-${env}-cost-guardrails`) explicitly **denies** the API calls that cause
the worst surprises. This is the mechanical enforcement of the skill's killer-services denylist:

- `ec2:CreateNatGateway` — the #1 silent bill (~$33/mo idle)
- `elasticloadbalancing:Create*` — ALB/NLB (~$16/mo+)
- `elasticache:Create*`, `redshift:Create*`, `sagemaker:Create*`, `eks:Create*`, `ecs:Create*`, `emr:RunJobFlow`, `transfer:CreateServer`, `es:CreateDomain` + more pricey-by-default services
- `ec2:RunInstances` for any instance type larger than `t4g.large` / `t3.medium`
- `ec2:CreateVolume` for volumes > 200 GB or io1/io2 (provisioned IOPS)
- `rds:CreateDBInstance` for anything larger than `db.t4g.medium`
- `rds:ModifyDBInstance` to enable Multi-AZ (doubles RDS cost)
- `rds:CreateDBInstance` with CloudWatch Logs export enabled ($0.50/GB ingest)

**Opt-in.** Created by Terraform but *not* attached. To activate:

```bash
aws iam attach-user-policy --user-name $YOUR_USER \
  --policy-arn $(cd personal/infra/terraform && terraform output -raw cost_guardrails_policy_arn)
# or join the pre-built group:
aws iam add-user-to-group --user-name $YOUR_USER \
  --group-name $(cd personal/infra/terraform && terraform output -raw cost_restricted_group_name)
```

### P2. AWS Service Quotas (manual, one-time)

AWS physically refuses to provision past a quota. Lower these once (free changes via Service Quotas):

- "Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances" → 8 vCPUs
- "Running On-Demand G/VT/Inf/P/X instances" → 0
- "DB instances" (RDS) → 3 ; "Storage for All DB Instances" → 200 GB

---

## Detection layers

### D1–D7. Account-wide Budgets (`personal/infra/`)

| Budget | Default | Catches |
|---|---|---|
| `monthly_cost` | $80 | total runaway; forecast emails at 25 % / 50 % / 80 % |
| `daily_anomaly` | $4/day | NAT Gateway, sudden spikes — same-day alert |
| `ec2` | $40 | bigger / extra instances |
| `rds` | $32 | RDS resize, Multi-AZ enable |
| `vpc` | $1 | NAT Gateway, VPC Endpoints, Transit Gateway |
| `elb` | $1 | ALB / NLB / Classic ELB creation |
| `data_transfer` | $5 | egress runaway — the #1 hidden cost |

### D8. Per-app tag-filtered budget (each product's `infra/`)

Counts only resources tagged `Project=<app>`. Catches "this app got expensive" independent of total
spend. Default $40. Lives in the per-app stack, **not** here.

### D9, D13–D14. Account-wide CloudWatch alarms (`personal/infra/`)

| Alarm | Threshold | Catches |
|---|---|---|
| EstimatedCharges | $120 ceiling | total — independent code path from Budgets (in case email delivery fails) |
| RDS FreeStorageSpace | < 20 % | runaway INSERT / autoscale headroom gone |
| RDS DatabaseConnections | > 150 | apps exhausting the shared connection pool |

### D10–D12. Per-app EC2 behavior alarms (each product's `infra/`)

NetworkOut (egress leak / exfil), CPUUtilization 90 % sustained (runaway / miner), EBS WriteOps storm.
These live with the app host, not here.

### D15. Cost Anomaly Detector

AWS's ML model — fires on any service deviating > ~$3 from baseline. Free. Needs ~14 days of history;
Budgets carry coverage during that window.

### D16. Weekly cost-audit script (`scripts/cost-audit.sh`)

Lists unattached EBS, snapshots > 30 days, running EC2, unattached Elastic IPs ($3.60/mo each), NAT
Gateways (expected: 0), load balancers (expected: 0), RDS instances (expected: 1 shared), log groups
+ retention, S3 buckets + sizes, and month-to-date spend. Acting on it is **not optional**.

---

## Manual one-time setup (before/after first apply)

1. **Confirm the SNS subscription email** AWS sends after the first apply. Until you click, *no alert reaches you*.
2. **Enable Free Tier usage alerts** — Billing console → Billing preferences. Independent of Budgets, free.
3. **Enable "Receive AWS Billing Alerts"** — same page; required for CloudWatch billing metrics (D9 depends on it).
4. **Lower service quotas** (P2). 5. **Attach the cost-guardrails policy** (P1). 6. **Set the IAM/root account password policy** — root compromise = unbounded bill.

---

## When a guardrail fires

| Email subject contains | Likely cause | First check |
|---|---|---|
| `shared-prod-vpc-anti-budget` | NAT Gateway / VPC Endpoint | `aws ec2 describe-nat-gateways` |
| `shared-prod-elb-anti-budget` | ALB / NLB created | `aws elbv2 describe-load-balancers` |
| `shared-prod-daily-anomaly` | something started costing money today | last cost-audit log + Cost Explorer last 24 h |
| `shared-prod-ec2` | bigger / extra instance | `aws ec2 describe-instances` |
| `shared-prod-rds` | RDS resize, Multi-AZ, or PIOPS | `aws rds describe-db-instances` |
| `shared-prod-data-transfer` | egress leak | EC2 NetworkOut alarm + what's reaching the box |
| `*network-out-high` | host pushing > 5 MB/s for 15 min | `iftop` / `docker stats` on the host |
| `*cpu-sustained-high` | runaway loop or compromise | `docker stats` / `top` |
| `*rds-low-disk` | DB filling up | `psql -c "\l+"` to see DB sizes |
| AWS Cost Anomaly Detection | per-service spike | the email names the service |

Reflex: identify the resource → confirm intended → kill if not → if intended, record the spend + its
kill condition in `personal/boardroom/docs/CAPITAL.md`. **A fired-and-ignored guardrail = no guardrail.**

---

## What's the budget cost of all this?

| Item | $/mo |
|---|---:|
| AWS Budgets — first 62 budget-days/mo free, $0.02/budget-day after | ~$2.80 |
| CloudWatch alarms — first 10 free per account, then $0.10 each | ~$0 |
| Cost Anomaly Detector / SNS email (<1k/mo) / SSM standard tier | $0 |
| Cost-audit script — runs on an existing instance | $0 |
| **Total** | **~$3/mo** |

Three dollars a month to never get surprised again is the deal.
