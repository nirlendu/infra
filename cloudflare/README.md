# personal/infra/cloudflare — the edge stack

Cloudflare config for every domain in this account, in code.

State: remote — `s3://nirlendu-tfstate-419105693501/cloudflare/terraform.tfstate`
(versioned, encrypted, native S3 locking). **`terraform plan` is clean (zero drift).**

## Why this stack exists

Every hostname here is Cloudflare-proxied (orange-cloud). That makes **Cloudflare
the real user-facing edge, and CloudFront merely an origin.** Anything Cloudflare
serves from its own cache never reaches AWS and never bills.

That fact was load-bearing and entirely undocumented until the August 2026
CloudFront incident. Measured on the `maxinterview.com` zone that month:

| | |
|---|---|
| Requests Cloudflare received | 229,945,671 |
| Bytes Cloudflare served | 7,904 GB |
| Cached at Cloudflare (free) | 148,349,973 — 64.5% |
| Leaked through to CloudFront | ~81.6M requests → **$152** |

Cloudflare was already absorbing two thirds of a bot crawl for free. The third
that leaked was **HTML**, because Cloudflare does not cache HTML by default —
it returns `cf-cache-status: DYNAMIC` and passes every request to origin.

## The two things worth internalising

**1. CloudFront caching does not reduce cost.** CloudFront bills full egress on
a cache *hit*. The only lever that lowers the AWS bill is not reaching
CloudFront at all — which makes Cloudflare's cache the control and CloudFront's
cache irrelevant to spend.

**2. Cache hit rate is not a cost/performance tradeoff.** A Cloudflare hit is
simultaneously cheaper (no AWS involvement) and faster (no origin round trip).
Raising it wins on both axes. The only thing traded away is content freshness —
which is exactly why zones are split by deploy cadence, not by cost.

## Layout

| File | What |
|---|---|
| `zones.tf` | Zone inventory, split `archived` (24h TTL) vs `active` (300s TTL) |
| `cache-rules.tf` | The main cost control |
| `rate-limits.tf` | Backstop only — read the honest caveats in the header |
| `bot-management.tf` | AI-crawler blocking on archived zones |
| `imports.tf` | Adoption of the hand-applied Sept 2026 fix. Safe to delete. |

## Zone policy

**`archived`** — nothing deploys, so a 24h edge TTL is free performance:
`maxinterview`, `nirlendu`, `superwomn`, `suprhealthe`.

**`active`** — under development, 300s edge TTL plus `/api/` bypass:
`geniusjnr`, `supertravelr`.

Moving a zone from `archived` to `active` **must** happen before it starts
shipping again, not after.

## Deploying an active zone

A 300s TTL means a deploy is fully live within five minutes on its own. For
immediacy:

```bash
make purge ZONE=geniusjnr
```

A Cloudflare purge clears the **edge only, not browsers** — which is why
`browser_ttl` is held at 300s rather than something longer.

## Not managed here — and why

| | |
|---|---|
| `authoxi.com`, `agitome.com` | aeternm products; edge owned by their own app terraform. Origins are API Gateway and **must never** be cache-everything'd. |
| `dailyapp.cc` | Proxied by a **second Cloudflare account** this token cannot see (`ns: jo.ns.cloudflare.com`). Unmanaged and invisible. |
| `indiabackpacks.com`, `plusfoods.in` | **Not on Cloudflare at all.** GoDaddy DNS (`domaincontrol.com`) pointing straight at AWS. No edge cache, no bot protection, no free tier in front. Least-protected surface in the estate. |

Those last two rows are open risks, not decisions.

## Auth

```bash
eval "$(make token)"    # loads CLOUDFLARE_API_TOKEN from SSM for this shell
```

The token lives at `/shared/prod/cloudflare/api-token`, declared in
[`../terraform/06-cloudflare-token.tf`](../terraform/06-cloudflare-token.tf).
It used to be a bare `export` in an operator's shell, which meant it existed on
exactly one laptop, nothing recorded that it existed or when it was last
rotated, and nothing unattended could purge a cache.

**Terraform owns the parameter, not its value.** `terraform plan` refreshes, and
refreshing an `aws_ssm_parameter` reads the value back — so a token managed the
ordinary way would end up in this account's Terraform state and readable by
anything that can plan the shared stack. `ignore_changes = [value]` means the
placeholder is written once on create and never touched again; the real token
goes in with `aws ssm put-parameter --overwrite` (the exact command is in the
header of that file).

`make token` reads it as **`cloudflare-edge`** — a role that can reach that one
parameter and the `cloudflare/*` tfstate prefix, and nothing else in the
account. Not `AdministratorAccess`, which is what this stack was applied as
before. Not `agent`, which is an authoxi allowlist and cannot see `/shared/*`.
If the parameter still holds the placeholder, `make token` says so and exits
rather than exporting a value that would fail later as a confusing 403.

Token scope: `Zone:Read`, `Zone Settings:Edit`, `Cache Rules:Edit`,
`Zone WAF:Edit`, `Bot Management:Edit`, and `Cache Purge` if you want
`make purge` to work (it is a separate permission — without it the purge call
returns `Authentication error`, code 10000, which is misleading: the token is
valid, it just cannot purge).

A Cloudflare token is an **account-wide bearer credential** — it can repoint DNS
for every domain here. That is why it gets a dedicated role rather than riding
along with an existing one.

**`Zone WAF` is the one people miss.** Rate limiting lives in the Rulesets API
and needs `Zone WAF` — *"Firewall Services"* is a different permission and is
not sufficient. The symptom is `403` on
`rulesets/phases/http_ratelimit/entrypoint` while `firewall/rules` returns
`200`. The legacy `rate_limits` endpoint returns `410 Gone`; there is no
workaround.

## Free plan ceilings

Discovered by having the API reject the values:

- Rate limit `period`: **only `10`** seconds accepted
- Rate limit `mitigation_timeout`: **only `10`** seconds accepted
- Tiered Cache: `editable: false` — unavailable

So the strongest rule available is 20 req/10s per IP, blocked for 10s. A single
IP can still sustain ~172,000 requests/day. Rate limiting here is damage
limitation on origin fetches; **the cache rules are the actual protection.**

## Gotchas

- Phase-entrypoint rulesets are always named `default` by Cloudflare. Any other
  `name` forces a **destroy-and-recreate**, which briefly drops protection on a
  zone under active crawl. Leave it as `default`.
- `fight_mode = true` is rejected unless `enable_js = true` is sent with it.
- `CacheHitRate` in CloudWatch returns *no datapoints* unless CloudFront
  additional metrics are enabled — easily misread as a 0% hit rate.

## Sibling stacks

- `../terraform` — greenfield shared-infra (VPC, RDS, budgets, SNS, SSM)
- `../existing` — imported live-AWS replica (S3, CloudFront, ACM)
