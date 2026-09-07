###############################################################################
# Zone settings — the free switches that were never turned on.
#
# These are not new capabilities. Every one of them has been available on the
# Free plan for the entire life of this account, and every one was left at a
# default that costs money. Verified live on maxinterview.com, 2026-09-03:
#
#   always_online        off      hotlink_protection   off
#   early_hints          off      security_level       medium
#
# Each resource below is one setting on one zone, so the plan reads as a list
# of exactly what changes. `value` is typed `dynamic` in the v5 provider — it
# takes a bare string for the settings used here.
###############################################################################

# ──────────────────────────────────────────────────────────────────────────────
# Always Online — serve from cache when the origin fails, instead of retrying.
#
# The cost argument, which is not the obvious one: when CloudFront returns an
# error (a 5xx, a throttle, an S3 hiccup), Cloudflare's default is to pass the
# failure through, and a crawler treats that as a signal to come back. With
# Always Online, Cloudflare answers from its own cache instead and the origin
# is not asked again. During the August incident every one of those retries was
# a billable CloudFront request.
#
# Applied to archived and active zones only. NOT to the topology-only product
# zones: serving a stale cached page for a live API-backed product is a
# correctness decision that belongs to that product, not to this file.
# ──────────────────────────────────────────────────────────────────────────────
resource "cloudflare_zone_setting" "always_online" {
  for_each = merge(
    { for k, v in local.archived_zones : k => v.zone_id },
    { for k, v in local.active_zones : k => v.zone_id },
  )

  zone_id    = each.value
  setting_id = "always_online"
  value      = "on"
}

# ──────────────────────────────────────────────────────────────────────────────
# Hotlink protection — stop other sites embedding our images at our expense.
#
# This is a pure egress control. Without it, any page anywhere can <img src>
# our assets and we pay the bandwidth for their visitors. On a portfolio of
# abandoned content sites with years of accumulated images — maxinterview alone
# holds 15 GB of them — that is a standing invitation nobody is watching.
#
# Deliberately NOT applied to the active or product zones: hotlink protection
# breaks legitimate embedding, and a live product may well want its OG images
# to render in someone else's link preview.
# ──────────────────────────────────────────────────────────────────────────────
resource "cloudflare_zone_setting" "hotlink_protection" {
  for_each = { for k, v in local.archived_zones : k => v.zone_id }

  zone_id    = each.value
  setting_id = "hotlink_protection"
  value      = "on"
}

# ──────────────────────────────────────────────────────────────────────────────
# Security level — raise the challenge threshold on abandoned zones.
#
# `high` challenges visitors with a poor IP reputation. On a live product that
# is a conversion cost and a real trade-off. On a site with no users and no
# repo, there is nothing to trade off: the only traffic is crawlers, and the
# worst case is that a crawler sees a challenge page.
#
# Search engines are unaffected — verified crawlers bypass this, which is why
# `crawler_protection` stays disabled in bot-management.tf for the same reason
# recorded there: SEO traffic is the entire remaining value of these domains.
# ──────────────────────────────────────────────────────────────────────────────
resource "cloudflare_zone_setting" "security_level_archived" {
  for_each = { for k, v in local.archived_zones : k => v.zone_id }

  zone_id    = each.value
  setting_id = "security_level"
  value      = "high"
}

# ──────────────────────────────────────────────────────────────────────────────
# Browser Cache TTL — hold the browser cache as long as the edge cache.
#
# The edge TTL and the browser TTL answer different questions: the first is how
# long until Cloudflare re-asks the origin, the second is how long until the
# visitor's browser re-asks Cloudflare. Cache rules already set the second
# per-rule; this is the zone-level floor for anything a rule does not match, so
# an unmatched asset does not fall back to "ask every time".
#
# Archived zones only. Active zones keep the 300s their cache rule sets, so a
# deploy is visible within five minutes.
# ──────────────────────────────────────────────────────────────────────────────
resource "cloudflare_zone_setting" "browser_cache_ttl_archived" {
  for_each = { for k, v in local.archived_zones : k => v.zone_id }

  zone_id    = each.value
  setting_id = "browser_cache_ttl"
  value      = 14400 # 4h, matching the cache rule's browser_ttl
}

# ──────────────────────────────────────────────────────────────────────────────
# TLS to the origin — mastersbound.com only, and only because it was wrong.
#
# The zone was created with GoDaddy's defaults and read, live on 2026-09-07:
#
#   ssl  full        always_use_https  off        min_tls_version  1.0
#
# `full` encrypts to the origin but does NOT validate the certificate, so a
# Cloudflare-to-origin hop can be intercepted by anything able to present any
# certificate at all. Every other zone in this account is already `strict`
# (geniusjnr, maxinterview, nirlendu, verified the same day) — this one was
# simply never brought in line, which is precisely the sort of thing that stays
# invisible until it is in Terraform.
#
# SCOPED TO ONE ZONE, DELIBERATELY, and this is the interesting part. The obvious
# form is `for_each = local.active_zones`, and it would have been wrong:
# supertravelr.com is on `flexible`, which means Cloudflare talks PLAIN HTTP to
# its origin. Flipping it to `strict` in a sweep aimed at mastersbound would be a
# live change to an unrelated product, made as a side effect. That zone needs its
# own look and its own change.
#
# Safe to apply before the cutover: the apex is still parked, so `strict` changes
# a 525 into a different 525 and no user is behind it.
# ──────────────────────────────────────────────────────────────────────────────
resource "cloudflare_zone_setting" "mastersbound_ssl" {
  zone_id    = local.active_zones.mastersbound.zone_id
  setting_id = "ssl"
  value      = "strict"
}

# CloudFront already answers http with a 301 (`redirect-to-https` on every cache
# behaviour), but that redirect costs a round trip to the origin edge. Answering
# it at Cloudflare is free, faster, and means a plaintext request never leaves
# the visitor's own region.
resource "cloudflare_zone_setting" "mastersbound_always_use_https" {
  zone_id    = local.active_zones.mastersbound.zone_id
  setting_id = "always_use_https"
  value      = "on"
}

# TLS 1.0 and 1.1 are deprecated and have been unsafe for years. The app's own
# distribution already floors at TLSv1.2_2021; this closes the same gap on the
# half of the path Cloudflare owns.
resource "cloudflare_zone_setting" "mastersbound_min_tls" {
  zone_id    = local.active_zones.mastersbound.zone_id
  setting_id = "min_tls_version"
  value      = "1.2"
}
