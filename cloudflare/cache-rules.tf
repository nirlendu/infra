###############################################################################
# Cache rules — the single highest-leverage cost control in this account.
#
# WHY THIS EXISTS
# Cloudflare does NOT cache HTML by default. Its default cache policy keys off
# file extension, so .css/.js/.png are cached and text/html is passed straight
# through as `cf-cache-status: DYNAMIC`. Every one of those pass-throughs is a
# billable CloudFront request AND billable CloudFront egress.
#
# That is not a theoretical cost. Measured on maxinterview.com, Aug 2026:
#   Cloudflare received      229,945,671 requests / 7,904 GB
#   Cloudflare cached         148,349,973 (64.5%) — free
#   leaked to CloudFront      ~81.6M requests     — $152
# The leak was almost entirely HTML.
#
# THE NON-OBVIOUS PART
# Caching at CloudFront does NOT help. CloudFront charges full egress on a
# cache HIT — it bills bytes leaving its edge regardless of where they came
# from. The only thing that reduces the AWS bill is not reaching CloudFront at
# all. That makes Cloudflare's cache the control, and CloudFront's cache
# irrelevant to cost.
#
# WHY IT IS SAFE HERE
# Every origin behind these zones is a static S3 website bucket. Verified at
# apply time: no Set-Cookie, no same-host JSON API, and on most of them a
# catch-all that returns the same shell for any path. Cache-everything on a
# host with per-user responses would serve one visitor's page to another — if a
# zone ever grows a real session or API, remove it from here FIRST.
###############################################################################

# ──────────────────────────────────────────────────────────────────────────────
# Archived zones — 24h edge TTL.
#
# Nothing deploys to these, so staleness costs nothing and a long TTL means a
# crawler making repeat passes is absorbed almost entirely at the edge.
# maxinterview alone was crawled ~364 times over the same ~110,000 URLs, which
# is exactly the shape a long TTL defeats.
# ──────────────────────────────────────────────────────────────────────────────
resource "cloudflare_ruleset" "cache_archived" {
  for_each = local.archived_zones

  zone_id = each.value.zone_id
  # Cloudflare names every phase-ENTRYPOINT ruleset "default" and will not accept
  # another value without replacing the ruleset. A replacement destroys the live
  # rule before recreating it, leaving these zones briefly unprotected while they
  # are being actively crawled. The terraform resource name carries the meaning.
  name  = "default"
  kind  = "zone"
  phase = "http_request_cache_settings"

  rules = [{
    action      = "set_cache_settings"
    expression  = "true"
    description = "Cache all responses at edge - static S3 origin, no personalization (billing protection)"
    enabled     = true
    action_parameters = {
      cache = true
      edge_ttl = {
        mode    = "override_origin"
        default = 86400 # 24h. Origin sends no Cache-Control, so override is required.
      }
      browser_ttl = {
        mode    = "override_origin"
        default = 14400 # 4h
      }
    }
  }]
}

# ──────────────────────────────────────────────────────────────────────────────
# Active zones — 300s edge TTL, with an API bypass.
#
# 5 minutes is the deliberate compromise. A crawler repeating over the same
# URLs is still absorbed (it re-requests far faster than every 5 min), while a
# deploy goes fully live within 5 minutes unmanaged. Pair with `make purge` for
# immediate propagation — a Cloudflare purge clears the edge, but NOT browsers,
# which is why browser_ttl is also held at 300s rather than something longer.
#
# The /api/ bypass is future-proofing, not a fix: neither zone serves a real
# API today (both return HTML on /api/health — geniusjnr's is literally the
# homepage catch-all). But "cache everything" plus a later-added JSON endpoint
# on the same host is a silent, ugly failure, and the rule costs nothing now.
#
# Ordered first and made mutually exclusive with the cache rule below, so
# exactly one rule matches any request. Do not rely on last-match-wins here.
# ──────────────────────────────────────────────────────────────────────────────
resource "cloudflare_ruleset" "cache_active" {
  for_each = local.active_zones

  zone_id = each.value.zone_id
  # Cloudflare names every phase-ENTRYPOINT ruleset "default" and will not accept
  # another value without replacing the ruleset. A replacement destroys the live
  # rule before recreating it, leaving these zones briefly unprotected while they
  # are being actively crawled. The terraform resource name carries the meaning.
  name  = "default"
  kind  = "zone"
  phase = "http_request_cache_settings"

  rules = [
    {
      action      = "set_cache_settings"
      expression  = "starts_with(http.request.uri.path, \"/api/\")"
      description = "Bypass cache for API paths (future-proofing; no API on these hosts today)"
      enabled     = true
      action_parameters = {
        cache = false
      }
    },
    {
      action      = "set_cache_settings"
      expression  = "not starts_with(http.request.uri.path, \"/api/\")"
      description = "Cache HTML at edge, 300s TTL - active product, purge on deploy"
      enabled     = true
      action_parameters = {
        cache = true
        edge_ttl = {
          mode    = "override_origin"
          default = 300
        }
        browser_ttl = {
          mode    = "override_origin"
          default = 300
        }
      }
    },
  ]
}
