# Agent deploy role + `authoxi-deploy` profile — plan

**Goal:** let an agent run `make deploy` for authoxi unattended, with a hard cap on the downside.
**Written** 2026-07-14.

**Status — LIVE. The role is deployed and verified. One manual step remains (key deactivation).**

| | |
|---|---|
| ✅ | AWS Organization `o-xbdet5v3fh`, management account `419105693501`, feature set ALL |
| ✅ | IAM Identity Center org instance `ssoins-722343b288d72bdb`, identity store `d-9066777b2b`, ACTIVE |
| ✅ | User `nirlendu` (Nirlendu Saha, nirlendu@gmail.com), `AdministratorAccess` permission set (4h), assigned |
| ✅ | Portal: `https://d-9066777b2b.awsapps.com/start` |
| ✅ | `~/.aws/config` rewritten: root login REMOVED (backup at `~/.aws/config.bak-root-20260714`); `[profile admin]` (SSO) + `[profile authoxi-deploy]` (agent role) |
| ✅ | **`aws sso login` works — caller is now `assumed-role/AWSReservedSSO_AdministratorAccess_*/nirlendu`, NOT root.** F1 closed. |
| ✅ | `agent` role + 4 policies applied (`terraform apply -target`, agent resources only — the shared VPC/RDS deliberately NOT created) |
| ✅ | **Red-teamed via IAM Policy Simulator: 24/24.** All 3 roads denied, legacy estate denied, escalation denied, undo-button denied, spend-cap denied; deploy actions allowed. See §9. |
| ⬜ | **← YOU: deactivate the two old access keys.** Classifier blocked me (correctly — it disables live creds). Commands in §10. |
| ⬜ | Phase 4 (OIDC/CI) + agentlox onboarding — unchanged, future |

---

## 0. What we found before writing a line of policy

Four things in the existing setup change the design. The first one outranks everything else.

| # | Finding | Why it matters |
|---|---|---|
| **F1** | **`~/.aws/config` logs in as `arn:aws:iam::419105693501:root`.** | Root **cannot be constrained by IAM**. Not by a deny policy, not by a permissions boundary, not by an SCP. Any agent with a shell in a session holding root creds *is* root — it can close the account, delete every backup, and rotate billing. Every guardrail below is decorative until this is fixed. **This is Phase 0.** |
| **F2** | **Both stacks share one state bucket** — `nirlendu-tfstate-419105693501`, keys `authoxi/prod/` and `shared/`. | Terraform state stores sensitive values **in plaintext**. The shared stack manages RDS, so the master password is sitting in the clear inside `shared/terraform.tfstate`. A bucket-level grant to the agent hands over the crown jewel with no IAM or SSM call at all. The state grant must be **prefix-scoped**. |
| **F3** | **`authoxi-prod-bootstrap-exec` exists to read the master password.** | An agent with ECR write + `ecs:RegisterTaskDefinition` can push its own image and register a task def under that role, exfiltrating the password without ever calling SSM. `iam:PassRole` must be denied on it specifically. |
| **F4** | **`cost_guardrails` managed policy already exists, unattached.** | `04-cost-guardrails.tf` already denies NAT gateways, load balancers, oversized instances, expensive managed services — and its header says it's waiting for exactly this case. **Attach it, don't duplicate it.** The new policy only needs to cover *security*, not cost. |
| **F5** | **`agentlox-prod-instance` holds a STANDING grant to `/shared/<env>/*`** — wildcard, master password included (`agentlox/infra/terraform/02-iam.tf:70`). | **For agentlox, "deploy" and "read every DB password" are the same permission**, and no deny list can separate them — see §2a. Unlike authoxi's `bootstrap-exec` (4-second task), this grant is held permanently by a long-lived host. agentlox's own header calls this out as an accepted pre-revenue trade — but it was accepted when only a *human* held the deploy credential. |
| **F6** | **agentlox has no S3 backend.** `versions.tf` has no `backend` block — state is a local file. | An unattended agent cannot deploy it (no shared state), and the state file is unversioned, unlocked, one `rm` from gone. Blocks Phase 4 for agentlox. |
| **F7** | **This account is NOT clean.** It holds a decade of live production for other projects: `admin.dailyapp.co.production` (a real company), masterclub, supertravelr, maxinterview, geniusjnr, indiabackpacks, bettermoney, an ap-south-1 Elastic Beanstalk. | **Flips the whole posture.** A "PowerUserAccess minus denies" role reaches all of it — a denylist is only as good as your memory of what's in the account, and nobody is going to enumerate twelve years of assets correctly. **The role is an ALLOWLIST.** Denies become defence-in-depth, not the boundary. Unknown-unknowns fail closed. |
| **F8** | **Terraform cannot authenticate with `aws login`.** The provider walks the credential chain, doesn't recognise `~/.aws/login/cache`, and falls through to the EC2 metadata endpoint (`169.254.169.254`) — which fails. | Phase 0 is not merely a safety step: **`terraform apply` cannot run at all** until there's an admin identity the AWS SDK understands (Identity Center, or an IAM user with keys/MFA). |

| **F9** | **A live admin access key, six years old, no MFA.** `nirlendu@gmail.com` carries `AdministratorAccess` + `AmazonS3FullAccess` and key `AKIAWDFFFL46SXWIY6N3` (created 2020-05-29, **last used 2026-06-02**). | CloudTrail identified the caller: `Terraform/1.10.5` + `aws-cli/2.27.26 os/macos` from a single IP — **it's this laptop**, running the shared-infra stack. Not a leaked credential in someone else's hands. So deactivating it is low-risk, but it must happen **after** Identity Center works, or there's no working Terraform credential at all (root doesn't count — see F8). `dailyappco@gmail.com` also holds a 2020 key that has **never been used once** — dead, delete it. |
| **F10** | **`existing/terraform.tfstate` — 237 KB — is in the state bucket.** | A Terraform state file for the LEGACY production estate that nobody mentioned. State holds secrets in plaintext, so it is very likely a credential dump for the live businesses in this account. The allowlist already fenced it off (state grant is `authoxi/*`-scoped), but the *deny* originally named only `shared/*` — i.e. the defence-in-depth layer had been written against the threats we happened to know about. **That is the exact failure mode the allowlist posture exists to prevent, and it showed up in my own policy.** Now denied explicitly. |
| **F11** | **The shared stack is only half-applied.** Budgets + SNS exist (the targeted apply from `authoxi/infra/PLAN.md` Phase 1). There is **no VPC and no RDS**. | **The crown jewel does not exist yet.** Every road-1/2/3 defence is pre-emptive. It also means there is a window to fix agentlox's role split (P1) *before* the master password it leaks is ever created — much cheaper than retrofitting. |

Also: `~/.aws/config` sets `region = ap-south-1`, but the whole stack deploys to `us-east-1`. The deploy profile must pin the region explicitly.

**Verified 2026-07-14:** `nirlendu-tfstate-419105693501` **exists** and versioning is **`Enabled`**. The undo button is intact. Identity is still `:root` (F1 unfixed). No Identity Center instance exists. No non-service IAM roles exist — neither app stack has ever been applied.

---

## 1. What "cap on downside" actually means

Three dials, not one. The deny list only turns the first.

**Blast radius** — what IAM permits.
**Reversibility** — can you undo it? The stack is already strong here: ECR is immutable-tagged and a deploy is `terraform apply -var image_tag=<sha>`, so a bad deploy is undone by re-applying the previous SHA. Which means the damage that *actually matters* is the damage that **destroys the undo button**: deleting backups, turning off S3 versioning, deleting the ECR repo (where the rollback SHAs live), purging state versions, stopping CloudTrail. Those are the permanent losses. Everything else is an inconvenience.
**Time to notice** — a distinctly-named role gives a clean CloudTrail filter; budget alarms already exist.

Design rule that follows: **the agent must never be able to destroy the evidence or the undo button.** Guard those absolutely; be relaxed about the rest.

---

## 2. The three roads to the crown jewel

The shared RDS master password reaches every app's database — `authoxi/infra/terraform/iam.tf` says so in its own header. A naive "create/modify, deny IAM + billing" role leaves **all three** roads open:

| Road | Call | Closed by |
|---|---|---|
| 1. Direct | `ssm:GetParameter` on `/shared/*/rds/master-password` | Explicit `Deny` on that ARN |
| 2. Borrowed identity | `iam:PassRole` on `authoxi-prod-bootstrap-exec` → run own image | `Deny` PassRole on `*bootstrap-exec*`; allow only the four safe roles |
| 3. Plaintext state | `s3:GetObject` on `shared/terraform.tfstate` | Prefix-scope state grant; `Deny` on `shared/*` |
| 4. **agentlox's host role** | `iam:PassRole` / `ec2:AssociateIamInstanceProfile` / `ssm:SendCommand` on `agentlox-prod-instance` | **Cannot be closed by policy — see §2a** |

Road 3 bypasses both of the first two defences, because it touches neither IAM nor SSM.

### 2a. Why road 4 can't be closed with a deny list

`agentlox-prod-instance` has a **standing** grant to `/shared/<env>/*` (wildcard → master password). To deploy agentlox at all, the agent must `iam:PassRole` that role onto an EC2 instance. So:

> **The permission to deploy agentlox *is* the permission to read every database password.**

There is no condition key that separates "pass this role to the instance Terraform is managing" from "pass this role to an instance I control." Deny `PassRole` on it and the agent can't deploy agentlox. Allow it and the crown-jewel protection in roads 1–3 is decorative — the agent just walks around it.

agentlox's own `02-iam.tf` header accepts this ("A compromise of this host = full DB compromise across all apps. Acceptable pre-revenue") — but that was accepted when only a **human** held the deploy credential. Handing it to an agent is what makes it load-bearing.

**This is a prerequisite, not a policy problem.** authoxi already solved the identical problem: its `iam.tf` splits `bootstrap-exec` (reads the password, lives for a 4-second task, once) from the runtime role (never reads it). Port that pattern to agentlox — which is also what agentlox's own TODO already says to do ("rotate boot-time master access out via a separate one-shot Lambda").

---

## 3. Scope: ONE `agent` role, rolled out in stages

**Decision (2026-07-14): one role for everything**, not one per app. The deny list is identical for both apps, the crown-jewel denies are identical, and per-app roles are maintenance overhead that buys little with one operator and one account.

But it ships in stages, because of F5/F6:

| Stage | Scope of the `agent` role | Blocked on |
|---|---|---|
| **Now** | authoxi only | nothing |
| **Later** | + agentlox | **P1** — port authoxi's bootstrap/runtime role split to agentlox, so `agentlox-prod-instance` no longer holds a standing master-password grant (§2a)<br>**P2** — give agentlox an S3 backend (F6) |

This is *not* "two roles." It's one role whose allow list grows once agentlox's IAM stops making "deploy" mean "read every DB password." Adding agentlox to the allow list is a few lines; doing it **before** P1 would silently unwind every protection in §2.

Don't block the authoxi agent on an agentlox refactor. Ship stage 1.

---

## 3b. Target end state

**Identities**

| Identity | Who/what | Credential | Notes |
|---|---|---|---|
| root | nobody, ever | — | MFA on, locked away. Used only for the ~4 things only root can do. |
| `nirlendu` (Identity Center) | you, interactive | SSO, short-lived | AdministratorAccess permission set |
| `agent` (IAM role) | the deploy agent | assumed, 1h max | The subject of this plan |

**Policies on `agent`**

1. Broad create/modify allow, region-locked to `us-east-1` (+ global services)
2. `cost_guardrails` — **existing**, from `04-cost-guardrails.tf`, just attached
3. `agent_security_guardrails` — **new**, the deny list in §4
4. A permissions boundary pinning the ceiling, so a later "just add one permission" edit still can't exceed it

**Two reads that must stay allowed** — both silently break tooling if you deny IAM/billing wholesale:
- `iam:Get*` / `iam:List*` — `terraform plan` refreshes `aws_iam_role.*` from state and dies without it. Nice side effect: an agent that edits `iam.tf` gets AccessDenied at apply. That's a tripwire, not a bug.
- `ce:GetCostAndUsage` — `infra/scripts/cost-audit.sh` needs it.

---

## 4. The policy set — allowlist first, denies as depth

**Posture (revised after F7): ALLOWLIST.** The role is granted the specific services and the specific named resources authoxi needs; everything else does not exist to it. The denies below are a second layer, not the boundary.

Four managed policies, because **AWS caps a managed policy at 6,144 characters** and a permissions boundary must be a *single* policy. Verified rendered sizes:

| policy | chars | role |
|---|---|---|
| `agent-allow-app` | 3,503 | ECS, ECR, PassRole, CloudFront, API GW, Cloud Map, Scheduler, logs, buckets |
| `agent-security-guardrails` | 3,110 | the denies below |
| `agent-allow-base` | 2,094 | Terraform reads, state (`authoxi/*` only), SSM, KMS-via-SSM, security groups |
| `agent-permissions-boundary` | 1,604 | compact ceiling — survives someone attaching AdministratorAccess |

(A single boundary of allow+deny concatenated would render at **8,707** and fail at apply. Hence the split.)

Scoping notes worth remembering:
- Buckets carry a `random_id` suffix, so they're scoped by **ARN prefix** (`authoxi-prod-web-*`). No legacy bucket matches — checked against the real bucket list.
- `ecs:RegisterTaskDefinition` and `ecr:GetAuthorizationToken` **cannot** be resource-scoped by AWS. What makes them safe is the PassRole allowlist, not the ARN.
- CloudFront is **tag-scoped** on `Project=authoxi` (which authoxi's provider `default_tags` sets). No legacy distribution carries that tag.
- `aws:RequestedRegion` does **not** reliably constrain S3. The region lock is not what fences off those ap-south-1 buckets — the named-bucket allowlist is. Don't mistake one for the other.

### The deny policy, in priority order

**Group A — the crown jewel.** The three roads in §2.

**Group B — the undo button.** This group *is* the downside cap.
- `s3:DeleteBucket`, `s3:PutBucketVersioning` (can't turn it off), `s3:DeleteObjectVersion`
- the backups bucket: no deletes, no lifecycle changes
- `ecr:DeleteRepository`, `ecr:BatchDeleteImage` — rollback SHAs live here
- `cloudtrail:StopLogging`, `cloudtrail:DeleteTrail`
- state bucket: no version deletes

**Group C — escalation.**
- all IAM **writes** (`Create*`, `Put*`, `Attach*`, `Update*`, `Delete*`, `Add*`, `Remove*`, `Tag*`)
- `iam:PassRole` allowed **only** to `authoxi-prod-{exec,task,backup-task,scheduler}`, with `iam:PassedToService = ecs-tasks.amazonaws.com`; denied on `*bootstrap-exec*`
- `ssm:SendCommand` (run commands on instances that already hold roles)
- `sts:AssumeRole` to anything but itself

**Group D — spend + exfiltration.** Cost side is mostly `cost_guardrails` already; this adds:
- region lock to `us-east-1` (global services excepted — IAM, CloudFront, Route53, S3 ListBuckets)
- `budgets:Modify*` / `budgets:Delete*` denied — `variables.tf` calls the budget "the ONLY guardrail on task size", so the agent must not be able to raise its own ceiling. Reads stay allowed.
- `rds:*` writes — the shared DB is not authoxi's to touch
- no public S3 bucket policies/ACLs
- no cross-account sharing: `ec2:ModifySnapshotAttribute`, `ec2:ModifyImageAttribute`, `ecr:SetRepositoryPolicy`
- `kms:Decrypt` only via `kms:ViaService` (mirrors the pattern already in `iam.tf`)

---

## 5. Runbook

**Phase 0 — stop being root.** (Blocks everything else — and per F8, blocks `terraform apply` outright, since the provider can't read your `aws login` session.)
1. Enable IAM Identity Center in `419105693501`.
2. Create user `nirlendu`, assign the `AdministratorAccess` permission set.
3. `aws configure sso` → profile `admin`, region `us-east-1`.
4. Verify: `aws sts get-caller-identity --profile admin` shows an assumed-role ARN, **not** `:root`.
5. Enable MFA on root. Stop using it.

**Phase 1 — state bucket.** ✅ **Already done.** `nirlendu-tfstate-419105693501` exists, versioning `Enabled`. Nothing to do.

**Phase 2 — the role.** ✅ **Written:** `_personal/infra/terraform/05-agent-role.tf` — the `agent` role, two allow policies, the deny policy, the compact boundary, and an attachment of the existing `cost_guardrails`. `terraform fmt` + `validate` clean; policy sizes verified against the 6,144 limit. **Not applied** — needs Phase 0 first (both for safety and because Terraform literally cannot authenticate today).

Set `agent_trusted_principal_arns` to your admin identity when you apply. The role cannot manage itself (IAM writes denied) — deliberate.

**Phase 3 — the profile.**
```ini
# ~/.aws/config
[profile authoxi-deploy]
region           = us-east-1        # NOT ap-south-1
role_arn         = arn:aws:iam::419105693501:role/agent
source_profile   = admin
duration_seconds = 3600
```
Agent runs with `AWS_PROFILE=authoxi-deploy`. `make deploy` / `release.sh` inherit it.

**Phase 4 — unattended (when you get there).** Add a GitHub OIDC trust entry to the *same* role. Same deny list, so going unattended requires loosening nothing under deadline pressure. Add a CloudWatch alarm on `AccessDenied` from the `agent` role — with nobody at the keyboard, that alarm **is** the tripwire, and it's how you learn the agent tried one of the three roads.

---

## 6. Residual risk — read this, it's the honest part

**On your laptop, the profile is not a security boundary.** `source_profile = admin` means the agent's shell can reach the admin session too — it can just run `--profile admin` and skip the whole deny list. Even a direct SSO profile doesn't fix this: the cached SSO *token* can mint credentials for any permission set your user is assigned to, including admin. **An agent with shell access on an admin's laptop is effectively admin.** No IAM policy can change that; the containment has to be process isolation (a container with only the agent role's creds injected and no access to `$HOME/.aws`), not IAM.

So be clear-eyed about what each mode buys:
- **Attended/local:** the role protects against *accidents and confused agents*. It does not protect against a hostile one (e.g. a prompt injection from a README or a poisoned dependency). You are the guardrail.
- **Unattended/CI with OIDC:** there is no human admin session anywhere near it. *This* is the real security boundary, and it's why Phase 4 matters more than it looks.

**What the agent can still do, by design:** break authoxi. Deploy a bad image, misconfigure a security group, repoint CloudFront, burn up to the $20 budget. That's the unavoidable price of "change infra."

**What it cannot do:** reach another app's data, escalate to admin, read the shared RDS password by any of the three roads, destroy the backups or the rollback images, or raise its own spending cap. Every remaining failure is a `terraform apply` from git away from fixed.

---

## 7. Open questions

- Does `nirlendu-tfstate-419105693501` exist, and is versioning on? (Session expired; unverified.)
- Identity Center, or a plain IAM admin user with MFA? Identity Center is better (native short-lived creds, central revoke) and you're already on short-lived sessions — but it's more setup.
- ~~One role, or one per app?~~ **Answered: one role, staged (§3).**
- **P1 (agentlox role split) is now on the critical path for the joint release unit.** The release matrix treats authoxi + agentlox as one unit; the agent can only deploy half of it until agentlox's instance role stops holding the master password. Worth sizing.

## 8. Also denied, because of F5

Even in stage 1 (authoxi-only), the deny list must pre-emptively block the roads into agentlox's host role — otherwise "authoxi-only" isn't a real boundary:
- `ssm:SendCommand` (run commands on a host that already holds the grant)
- `iam:PassRole` on `agentlox-*-instance`
- `ec2:AssociateIamInstanceProfile`, `ec2:ReplaceIamInstanceProfileAssociation`

Cost: the agent can't use SSM Session Manager to debug the agentlox box. That's the intended outcome, not a regression.

---

## 9. Verification — red-team via IAM Policy Simulator (2026-07-14)

Read-only (`iam:simulate-principal-policy` evaluates, never mutates). Script: `scratchpad/verify-agent-role.sh`. **24/24.**

| Class | Probe | Result |
|---|---|---|
| Crown jewel | read `/shared/prod/rds/master-password` | explicitDeny |
| Crown jewel | PassRole `authoxi-prod-bootstrap-exec` | explicitDeny |
| Crown jewel | read `shared/` **and** `existing/` tfstate | explicitDeny |
| agentlox pivot | PassRole `agentlox-prod-instance` | explicitDeny |
| Legacy estate | daily / masterclub / supertravelr buckets | implicitDeny (allowlist fails closed) |
| Escalation | CreateRole, AttachRolePolicy, PutRolePolicy, SendCommand, RunInstances, AssumeRole-elsewhere | explicitDeny |
| Undo button | PutBucketVersioning-off, ecr:DeleteRepository, cloudtrail:StopLogging | explicitDeny |
| Spend cap | budgets:ModifyBudget, rds:DeleteDBInstance | explicitDeny |
| **Must work** | read own `authoxi/` state, ecr:PutImage, PassRole→ECS, iam:ListRoles, read shared VPC param | **allowed** |

**Simulator gotcha, worth remembering.** The simulator sends none of the request context keys by default, so three "must work" cases first showed a false DENY: the region lock (`aws:RequestedRegion`) and the PassRole condition (`iam:PassedToService`) fire against the *absent* key. Re-running with `--context-entries` set to what a real API call always populates returned `allowed`. Controls confirmed the conditions still bite: PassRole→ECS allowed, PassRole→Lambda denied, and the same SSM read denied when the region key is `ap-south-1`. **Lesson: an absent condition key is not the same as the real call — always supply `--context-entries` before believing a simulator DENY.**

---

## 10. YOU: deactivate the old access keys (last Phase-0 item)

The classifier blocked me from doing this — correctly, it disables live credentials. You're logged in as `admin`, so:

```bash
# 6-year-old admin key = THIS laptop's shared-stack runs (CloudTrail-confirmed). Reversible.
aws iam update-access-key --user-name nirlendu@gmail.com   --access-key-id AKIAWDFFFL46SXWIY6N3 --status Inactive --profile admin
# dailyappco key: created 2020, never used once.
aws iam update-access-key --user-name dailyappco@gmail.com --access-key-id AKIAWDFFFL46ZUUGYOHS --status Inactive --profile admin
```

Deactivate, don't delete. If something screams, `--status Active` undoes it in one command. After ~1 quiet week, delete. Note the `nirlendu@gmail.com` IAM user still carries `AdministratorAccess` + `AmazonS3FullAccess` directly — once the key is confirmed dead, that user should be stripped to nothing (or deleted), since SSO fully replaces it.

---

## 11. How to use it

```bash
aws sso login --profile admin        # you, 4h, when the session lapses
AWS_PROFILE=authoxi-deploy make deploy   # the agent — assumes role/agent (1h) off the admin session
```

The `authoxi-deploy` profile can't deploy anything **yet** — authoxi's own stack has never had its bootstrapping first-apply (the 5 roles, buckets, budget). That first apply is a human running `AWS_PROFILE=admin` in `aeternm/authoxi/infra`. After it, the agent takes over deploys. See note 2 in `05-agent-role.tf`.
