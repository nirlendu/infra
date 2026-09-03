###############################################################################
# Tiered caching — the setting that decides how many places may ask the origin.
#
# WHY THIS IS THE HIGHEST-LEVERAGE FILE IN THE STACK
#
# Cache rules decide WHAT is cacheable. They were written first, they are
# correct, and they were not enough: through early September the origin was
# still taking 80,000-250,000 requests/hour with `cf-cache-status: HIT` on the
# same URLs. The missing half is WHERE the cache lives.
#
# Without tiered caching, each of Cloudflare's ~330 data centres keeps its own
# independent cache and fetches from the origin itself. The August crawl
# arrived from eight regions at once — US, EU, AP, ZA, ME, CA, IN, JP — so a
# single URL could cost eight or more origin fetches while every one of those
# data centres reported a perfectly healthy local hit rate. The hit-rate metric
# and the bill were both telling the truth about different things.
#
# Tiered caching puts one upper tier in front of the origin. Lower tiers ask
# the upper tier; only the upper tier asks CloudFront. The same crawl collapses
# to roughly one origin fetch per object per TTL, regardless of how many
# regions it comes from.
#
# WHY IT IS SAFE ON EVERY ZONE, INCLUDING THE API ONES
#
# This changes nothing about cacheability. An object that was uncacheable stays
# uncacheable and still reaches the origin every time; an object that was
# cacheable is now fetched from fewer places. There is no configuration here
# that can serve one visitor's response to another, which is why this file
# covers `local.all_zones` while cache-rules.tf deliberately does not.
#
# WHY BOTH RESOURCES
#
# They are two settings, not one, and the second does nothing without the
# first:
#   argo_tiered_caching  — turns tiered caching on at all
#   tiered_cache (smart) — lets Cloudflare PICK the upper tier per origin from
#                          its own latency data, instead of using the generic
#                          topology
# Smart topology is the one that matters for us: our origins are in us-east-1
# and ap-south-1, and the generic topology has no way to know that. Both are
# free on the Free plan — verified against Cloudflare's plan matrix, and
# verified OFF on every zone in this account on 2026-09-03 before this landed.
#
# COST: nothing. This is the rare control that is free, reduces the bill, and
# also makes the sites faster.
###############################################################################

# ──────────────────────────────────────────────────────────────────────────────
# Step 1 — enable tiered caching.
# ──────────────────────────────────────────────────────────────────────────────
resource "cloudflare_argo_tiered_caching" "all" {
  for_each = local.all_zones

  zone_id = each.value
  value   = "on"
}

# ──────────────────────────────────────────────────────────────────────────────
# Step 2 — let Cloudflare choose the upper tier.
#
# depends_on is deliberate. Smart topology is a refinement OF tiered caching;
# applying it to a zone where tiered caching is still off is an ordering the
# API accepts and then silently does nothing useful with. Terraform has no way
# to infer the relationship between two independent zone settings, so it is
# stated.
# ──────────────────────────────────────────────────────────────────────────────
resource "cloudflare_tiered_cache" "smart" {
  for_each = local.all_zones

  zone_id = each.value
  value   = "on"

  depends_on = [cloudflare_argo_tiered_caching.all]
}
