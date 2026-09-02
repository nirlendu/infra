###############################################################################
# Zone inventory.
#
# Zones are split by how aggressively we may cache HTML, which is driven by one
# question: how often does the content change?
#
#   archived — no active deployment. Long edge TTL is free performance. If the
#              site ever ships again, move it to `active` FIRST.
#   active   — under development. Short edge TTL so a deploy goes live in
#              minutes, with `make purge` for immediacy.
#
# Zones NOT managed here, deliberately:
#   authoxi.com / agitome.com  — aeternm products. Their edge is owned by their
#     own app terraform (aeternm/*/infra/terraform/cdn.tf) and their origins are
#     API Gateway, which must never be cache-everything'd.
#   dailyapp.cc  — proxied by a SECOND Cloudflare account this token cannot
#     see (ns: jo.ns.cloudflare.com). Unmanaged. See README.
#   indiabackpacks.com / plusfoods.in  — NOT on Cloudflare at all. GoDaddy DNS
#     (domaincontrol.com) pointing straight at AWS. No edge cache, no bot
#     protection, no free tier in front of them. See README.
###############################################################################

locals {
  # Long-TTL zones: abandoned or static-forever. 24h edge cache.
  archived_zones = {
    maxinterview = {
      zone_id = "e2450d7f14fdcf30e34212613f7eaa16"
      note    = "Abandoned product, no repo in Documents/Code. 86% of the Aug 2026 CloudFront bill."
    }
    nirlendu = {
      zone_id = "50d402d707b43a6717ee06aaf1d79f81"
      note    = "Personal site, static."
    }
    superwomn = {
      zone_id = "b04e6e45e899cf5c6b349964fdc86643"
      note    = "Dormant. Was serving DYNAMIC (uncached) HTML — same failure mode as maxinterview."
    }
    suprhealthe = {
      zone_id = "68de4bb68b0882c0dbc4db705cfc3fc1"
      note    = "Dormant. Was serving DYNAMIC (uncached) HTML."
    }
  }

  # Short-TTL zones: live products under active deployment.
  active_zones = {
    geniusjnr = {
      zone_id = "04215cd92c731147fe3cf48f016efc5a"
      note    = "Active. Was at 2.8% cache hit rate — 97% of requests hitting origin for nothing."
    }
    supertravelr = {
      zone_id = "26402352e1cd08e18793200675137760"
      note    = "Active. Includes visa.supertravelr.com (not yet live; cached by explicit decision, purge on deploy)."
    }
  }

  # Zones that get a rate-limit rule. Only where request VOLUME is the risk;
  # a rule on a zone nobody crawls is just a rule to maintain.
  ratelimit_zones = {
    maxinterview = local.archived_zones.maxinterview.zone_id
    geniusjnr    = local.active_zones.geniusjnr.zone_id
    supertravelr = local.active_zones.supertravelr.zone_id
  }

  # Bot protection. Applied to archived zones only: blocking AI crawlers on a
  # live product is a content-distribution decision, not an infra one, and
  # should be made deliberately per product rather than inherited from here.
  bot_zones = { for k, v in local.archived_zones : k => v.zone_id }

  # Extensions exempted from rate limiting. A single page view pulls dozens of
  # these; counting them would throttle real users long before any crawler.
  static_extensions = [
    ".css", ".js", ".png", ".jpg", ".jpeg", ".gif",
    ".svg", ".ico", ".woff", ".woff2", ".webp", ".map",
  ]

  static_asset_expression = format(
    "not (%s)",
    join(" or ", [
      for e in local.static_extensions :
      format("ends_with(http.request.uri.path, %q)", e)
    ])
  )
}
