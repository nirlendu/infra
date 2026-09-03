# Cost Guardrails — Layered Defense (account-wide)

> **Goal:** never see an unexpected AWS bill again.
> If any one mechanism here fails, the next one catches it.

This is the **account-wide** cost doctrine for the whole AWS account — owned by `personal/infra/`
(shared-infra) and consumed by every product. The judgment layer that decides *whether to spend at
all* is the boardroom `cost-guardrails` skill (`_personal/boardroom/canon/skills/cost-guardrails/`);
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
                        ├────────────────────────────────────────┤
   Cloudflare edge      │  P3. Cache HTML at the edge so traffic  │
   (personal/infra/     │      never reaches CloudFront at all;   │
    cloudflare/)        │      AI-crawler block; rate limiting    │
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
                        │  D7. Data transfer — $5 (NOT CloudFront)│
                        │  D17. ECS/Fargate — $25 (task size/count)│
                        │  D18. CloudFront — $15 (CDN egress+reqs)│
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
- `elasticache:Create*`, `redshift:Create*`, `sagemaker:Create*`, `eks:Create*`, `emr:RunJobFlow`, `transfer:CreateServer`, `es:CreateDomain` + more pricey-by-default services
- `ec2:RunInstances` for any instance type larger than `t4g.large` / `t3.medium`
- `ec2:CreateVolume` for volumes > 200 GB or io1/io2 (provisioned IOPS)
- `rds:CreateDBInstance` for anything larger than `db.t4g.medium`
- `rds:ModifyDBInstance` to enable Multi-AZ (doubles RDS cost)
- `rds:CreateDBInstance` with CloudWatch Logs export enabled ($0.50/GB ingest)

**`ecs:CreateCluster` was removed from this list on 2026-07-14** — read this before putting it back.
An ECS cluster is a free control-plane object; unlike EKS ($73/mo just to exist) it costs nothing by
itself. Fargate bills per vCPU-second on the **tasks**, and the sanctioned per-app design (0.25 vCPU
ARM64) runs ~$8.50/mo — *cheaper than the t4g.small EC2 host it replaces*. Denying the cluster would
have bought nothing while blocking the cheaper option.

The two things that can actually run away on Fargate — **task size** and **task count** — have no IAM
condition key, so they cannot be denied at all. They are caught by **D17** (the ECS budget) and by
**cost-audit §8**, which flags any task larger than 0.25 vCPU. Fargate's real cost traps are NAT
Gateway and load balancers, and those are still denied above: the sanctioned design (API Gateway HTTP
API → VPC link → Cloud Map → task in a public subnet) needs neither. See `aeternm/authoxi/infra/PLAN.md`.

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
| `data_transfer` | $5 | egress on the `AWS Data Transfer` service line (EC2 / inter-region / S3). **Does NOT cover CloudFront** — see D18 |
| `ecs` (**D17**) | $25 | Fargate task resize or task-count runaway — **the only guardrail on either** |
| `cloudfront` (**D18**) | $5 | CDN egress + requests. Normal is **$0** (free tier), so any sustained spend here is abnormal by definition. Lowered from $15 on 2026-09-03 — see below |

### D19–D21. USAGE budgets — the only layer that sees a free-tier cliff coming

Every budget above measures **dollars**, and dollars are blind below a free
tier. July 2026 carried 645 GB and 23M CloudFront requests and billed **$0.00**,
so `cloudfront` read $0.00 ACTUAL / state OK for the whole month while the crawl
that produced August's $172 was already three weeks old. Nothing was broken.
A cost budget cannot warn about a cliff, because on the near side the cost is
zero and on the far side it is all of it at once.

A `USAGE` budget accrues from the first byte. These are set at **half the free
tier**, alerting at 40% — so the first email lands at roughly 20% of free-tier
consumption, about four days into an August-rate crawl rather than three weeks.

| Budget | Limit | First alert | Catches |
|---|---|---|---|
| `cf-bytes-usage` (**D19**) | 500 GB | 200 GB | egress ramp, weeks before a dollar |
| `cf-requests-usage` (**D20**) | 5M requests | 2M | the *leading* indicator — August crossed 10M requests on the 9th but 1 TB only on the 20th |
| `s3-requests-usage` (**D21**) | 3M requests | 1.2M | the 11.8M GETs that were half of August's S3 bill |

### D22–D24. Account-wide alarms that cannot go stale

D9–D21 are either account totals or hand-written lists. The per-distribution
alarms name the resource — which is what a budget can never do — but they cover
five distributions of thirty-five, and that list is guaranteed to rot as
distributions are replaced or added.

These use CloudWatch `SEARCH()`, which resolves its matching series at
**evaluation** time. There is no list to fall out of date: a distribution
created five minutes ago is inside the alarm automatically.

| Alarm | Threshold | Why that number |
|---|---|---|
| `cf-account-requests` (**D22**) | 333,333/day | the 10M/month free tier **as a daily run rate** — a day above it means the month is billable |
| `cf-account-bytes` (**D23**) | ~34 GiB/day | the 1 TB/month free tier as a daily run rate |
| `s3-direct-egress` (**D24**) | 5 GB/day | **the bypass hole.** 19 of 35 distributions have `s3-website` origins whose endpoints answer HTTP 200 directly, skipping Cloudflare *and* CloudFront. S3 egress is $0.09/GB with 100 GB free — a more expensive way to lose the same money, and nothing else here would see it |

> **D22 and D23 are expected to be in ALARM on first apply.** The account is
> running ~2M requests/day against a 333k threshold. That is the alarm correctly
> reporting a live incident, not a mis-calibration. **Them going green is the
> measurement** that the Cloudflare edge work succeeded.
>
> D24 may sit in `INSUFFICIENT_DATA`: S3 request metrics are not enabled per
> bucket by default and cost $0.20/million to collect. The alarm is declared
> anyway so the gap is visible in code rather than only in prose.

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

## Post-mortem: August 2026 — the layers fired and it did not help

The stated goal of this document is "never see an unexpected AWS bill again".
In August 2026 we saw one: **$271.57** against an $18–63 baseline, ~₹26,000.
Worth being precise about how, because the obvious lesson is the wrong one.

**What happened.** Two abandoned `maxinterview.com` CloudFront distributions
were crawled by bots — ~69M requests and 2,475 GB in a month. CloudFront came
to $171.27, 63% of the bill. The active portfolio was irrelevant: authoxi and
agitome together cost **$0.05**.

**Why it stayed invisible for three weeks.** Three separate failures, only one
of which was a missing guardrail:

1. **Wrong service scope.** `data_transfer` (D7) filters on the `AWS Data
   Transfer` service line. CloudFront bills under `Amazon CloudFront`. The
   budget read **$0.00 ACTUAL, state OK** for the entire incident. The one
   tripwire aimed at egress was pointed at the wrong wire. → fixed by **D18**.

2. **The free-tier cliff.** CloudFront's always-free tier is 1 TB + 10M
   requests/month. July already carried 645 GB / 23M requests and still billed
   **$0.00** for transfer. There was no gradient to notice — cost appears only
   after the cliff, and then all at once. ~3x the traffic produced ~8.5x the
   bill. Any budget whose threshold assumes "normal + margin" is blind to this
   shape; D18 is set against *zero*, not against normal.

3. **Delivery, not detection.** This is the uncomfortable one. `monthly_cost`
   (D1) was in **ALARM** at both 100% and 120%. `daily_anomaly` (D2) was in
   **ALARM**. The Cost Anomaly Detector (D15) was live with a **$3** absolute
   threshold on **daily** frequency. All of them emailed `nirlendu@gmail.com`,
   for roughly three weeks. **Every detection layer worked exactly as
   designed.** Nobody acted.

**The lesson.** Adding a twelfth budget would have changed nothing. Layers 1
and 2 were real gaps and are closed. Layer 3 is not a guardrail problem — it is
that one Gmail inbox is not a control surface, and that a budget alert says
"over budget" without naming a service, so even a read alert does not tell you
where to look.

**Still open** (deliberately recorded rather than quietly dropped):

- Route budget + anomaly SNS to something with attention — SMS, Slack — or add
  a **circuit breaker** that does not need a human: budget alarm → SNS →
  Lambda that disables the offending distribution or flips Cloudflare to
  "Under Attack". That is the only layer that works while asleep.
- AWS **Budgets Reports** (console-only, no API/CLI) can send one consolidated
  daily email across all budgets instead of N independent alarms. It reports
  *which budget*, still not *which service*.
- CloudFront access logging is **off**, so a repeat incident is not
  diagnosable after the fact.

**What was added in response:** D18 (CloudFront budget) and **P3** — the
Cloudflare edge stack at `personal/infra/cloudflare/`. P3 matters more than
D18: it is *prevention*, not detection. Traffic absorbed at Cloudflare's edge
never reaches CloudFront and cannot bill, whereas D18 only tells you after the
money is spent.

---

## Reversal — how to undo every control here

A control you are afraid to turn off is a control you will hesitate to turn on.
Every change in the 2026-09-03 set is reversible, and this is the exact
procedure for each. **Nothing below requires a console click or a CLI mutation.**

| Change | Reversal | Notes |
|---|---|---|
| Tiered caching | set `value = "off"` in `cloudflare/tiered-cache.tf` | See the caveat below — these are settings, not objects |
| Cache key / 4xx TTL | delete the `cache_key` and `status_code_ttl` blocks | Ruleset updates **in place**; no window without a rule |
| Zone settings | set `value` back (`always_online` → `"off"`, `security_level` → `"medium"`) | Same caveat |
| WAF rules | set `enabled = false`, or delete the ruleset | The escalation rule already ships disabled |
| `PriceClass_100` | set back to `PriceClass_All` | In-place update, no distribution replacement |
| S3 lifecycle | delete the resource | Removes the rule; **no object is ever deleted by it** |
| Usage budgets / alarms | delete the resource | Pure observation, nothing depends on them |
| Circuit breaker | `breaker_armed = false` (observe-only), or delete the Lambda | Observe-only still logs and notifies |
| `ignore_changes = [enabled]` | remove `enabled` from the lifecycle block | Terraform resumes owning the field |
| IAM phase 1 | delete `iam-legacy.tf` | Purely additive; removes only what it added |
| IAM phase 2 | re-declare the two attachments and the group membership | The users are never deleted, so nothing is unrecoverable |

**The one caveat, and it is a real one.** `cloudflare_argo_tiered_caching`,
`cloudflare_tiered_cache` and `cloudflare_zone_setting` are zone *settings*, not
creatable objects, and `terraform plan` says so:

> This resource cannot be destroyed from Terraform. If you create this resource,
> it will be present in the API until manually deleted.

So `terraform destroy` does **not** turn these off — it forgets them while they
stay on. The reversal is to set `value = "off"` and apply, which does work. This
matters because "destroy the resource" is the reflex, and here the reflex leaves
the setting live.

**Nothing in this set is irreversible.** No distribution is disabled, no object
is expired, no user or key is deleted, and no bucket policy is changed.

---

## Resilience — what happens when something is redeployed

A guardrail that watches a resource by ID stops watching the moment that
resource is replaced, and gives no signal that it has stopped. That is the same
failure as the `data_transfer` budget pointed at the wrong service line: green,
and measuring nothing. These are the enumerations in this account and what each
does when the estate moves under it.

| Layer | Binds to | On replacement | On a NEW resource |
|---|---|---|---|
| Per-distribution alarms (`existing/`) | Terraform **resource reference** | follows automatically | **not covered** |
| Breaker allowlist | SSM, published from the same references | follows on next apply of `existing/` | not covered (by design — safe) |
| Account-wide alarms (`08-…`) | `SEARCH()`, resolved at **evaluation** time | follows | **covered automatically** |
| CloudFront usage budgets | 10 hardcoded region prefixes | n/a | a **new AWS region is a gap** |
| S3 request usage budget | `UsageTypeGroup` | n/a | covered |
| Per-app budgets | `Project` tag | follows | covered **if tagged** |
| `monthly_cost`, `daily_anomaly` | whole account | follows | covered |

**The design rule that follows:** the enumerated layers exist to *name the
resource*, which is the thing a budget can never do and the thing you need at
3am. The `SEARCH()` layer exists so that naming is never the only coverage. Add
to the enumerations when you learn something new; do not rely on them being
complete.

**Two live gaps, recorded rather than papered over:**

- A **new AWS billing region** falls outside the CloudFront usage budgets'
  region list. The account-wide `SEARCH()` alarms catch it, which is why they
  exist alongside rather than instead.
- **Untagged spend.** In September the `Project` tag resolved for `authoxi`,
  `agitome`, `uni` and `shared-infra` — but 94% of spend was untagged, because
  it is the legacy estate and cost-allocation tags are not retroactive (they
  were activated 2026-09-02). Per-app budgets therefore cover the products and
  not the legacy footprint; the account-wide layers cover the rest.

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
| `shared-prod-ecs` | Fargate task got bigger, or task count grew | `cost-audit.sh` §8 — compare `cpu/mem` and `desired` against the app's PLAN |
| `shared-prod-daily-anomaly` | something started costing money today | last cost-audit log + Cost Explorer last 24 h |
| `shared-prod-ec2` | bigger / extra instance | `aws ec2 describe-instances` |
| `shared-prod-rds` | RDS resize, Multi-AZ, or PIOPS | `aws rds describe-db-instances` |
| `shared-prod-data-transfer` | egress leak | EC2 NetworkOut alarm + what's reaching the box |
| `*network-out-high` | host pushing > 5 MB/s for 15 min | `iftop` / `docker stats` on the host |
| `*cpu-sustained-high` | runaway loop or compromise | `docker stats` / `top` |
| `*rds-low-disk` | DB filling up | `psql -c "\l+"` to see DB sizes |
| AWS Cost Anomaly Detection | per-service spike | the email names the service |

Reflex: identify the resource → confirm intended → kill if not → if intended, record the spend + its
kill condition in `_personal/boardroom/docs/CAPITAL.md`. **A fired-and-ignored guardrail = no guardrail.**

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
