###############################################################################
# Rate limiting — a backstop, NOT the defense.
#
# Be honest about what this buys on the Free plan. Cloudflare hard-pins both
# knobs and rejects anything else at the API:
#
#   period              only 10 is permitted  ("not entitled to use the period 60")
#   mitigation_timeout  only 10 is permitted  ("not entitled to use a mitigation
#                                               timeout different from 10")
#
# So the strongest rule available is "20 requests per 10s per IP, blocked for
# 10s". A single IP can still sustain ~2 req/s ≈ 172,000 requests/day, and a
# crawler spread over 100 IPs could still push millions. The Aug 2026 peak was
# ~138 req/s, which this WOULD have throttled — but it would not have stopped a
# distributed crawl.
#
# The cache rules are what actually protect the bill: traffic that gets past
# this rule is still served from Cloudflare's edge and still costs AWS nothing.
# Treat rate limiting as damage-limiting on origin fetches, nothing more.
#
# If these limits ever start mattering, Pro ($20/mo) unlocks real periods and
# timeouts — cheap next to a $271 month, but only worth it if caching is
# already correct and still insufficient.
#
# Verified live on maxinterview.com: 60 concurrent requests in 3.9s produced
# 33x 200 and 27x 429, then normal human-paced browsing returned 5/5 200s.
###############################################################################

resource "cloudflare_ruleset" "ratelimit" {
  for_each = local.ratelimit_zones

  zone_id = each.value
  # Cloudflare names every phase-ENTRYPOINT ruleset "default" and will not accept
  # another value without replacing the ruleset. A replacement destroys the live
  # rule before recreating it, leaving these zones briefly unprotected while they
  # are being actively crawled. The terraform resource name carries the meaning.
  name  = "default"
  kind  = "zone"
  phase = "http_ratelimit"

  rules = [{
    action = "block"
    # Static assets are exempt: one page view pulls dozens of them, so counting
    # them would trip the limit on a real user long before any crawler.
    expression  = local.static_asset_expression
    description = "Throttle crawlers: >20 page-requests/10s per IP (static assets exempt)"
    enabled     = true

    ratelimit = {
      # cf.colo.id scopes the counter per edge location, which is required on
      # this plan and also means the effective global limit is higher than 20.
      characteristics     = ["ip.src", "cf.colo.id"]
      period              = 10 # Free plan: 10 only.
      requests_per_period = 20
      mitigation_timeout  = 10 # Free plan: 10 only.
    }
  }]
}
