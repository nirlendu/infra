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
    mastersbound = {
      zone_id = "34e6ae92b07d4623fda9c5c40a33d021"
      note    = "Active. THE FIRST ZONE HERE THAT SERVES A REAL AUTHENTICATED API — see the /api/ note in cache-rules.tf. Apex only; was 525 (no origin) until the Mastersbound cutover."
    }
  }

  # Zones that get TOPOLOGY ONLY — tiered caching, and nothing else.
  #
  # These are aeternm product zones whose CACHING belongs to their own app
  # terraform, for the reason stated above: their origins are API Gateway and a
  # cache-everything rule on them would serve one tenant's response to another.
  # That separation is right and this does not weaken it — nothing here creates
  # a cache rule, changes a TTL, or makes anything cacheable that was not
  # already.
  #
  # Tiered caching is a different kind of setting. It does not decide WHAT is
  # cacheable; it decides how many of Cloudflare's ~330 data centres are
  # allowed to ask the origin for it. On a zone with no cache rules the answer
  # is "the same objects as before, fetched from fewer places", which is safe
  # on any origin including API Gateway.
  #
  # They live here rather than in each app stack because a topology setting
  # that is set in five places is a topology setting that drifts. See the
  # tiered-cache.tf header for the full argument.
  topology_only_zones = {
    authoxi = {
      zone_id = "1494bb422214793c077470d42ccc169b"
      note    = "aeternm product. Caching owned by authoxi/authoxi-app-v1/infra/terraform/cdn.tf."
    }
    agitome = {
      zone_id = "8156567dac29ef1ce198d48eb6ac243b"
      note    = "aeternm product. Caching owned by agitome/agitome-app-v1/infra/terraform/cdn.tf."
    }
  }

  # Every zone this stack touches at all. Tiered caching is the only thing
  # applied uniformly across the whole set — everything else is deliberately
  # scoped by how the zone is used.
  all_zones = merge(
    { for k, v in local.archived_zones : k => v.zone_id },
    { for k, v in local.active_zones : k => v.zone_id },
    { for k, v in local.topology_only_zones : k => v.zone_id },
  )

  # Zones that get a rate-limit rule. Only where request VOLUME is the risk;
  # a rule on a zone nobody crawls is just a rule to maintain.
  ratelimit_zones = {
    maxinterview = local.archived_zones.maxinterview.zone_id
    geniusjnr    = local.active_zones.geniusjnr.zone_id
    supertravelr = local.active_zones.supertravelr.zone_id
    mastersbound = local.active_zones.mastersbound.zone_id
  }

  # Bot protection. Applied to archived zones only: blocking AI crawlers on a
  # live product is a content-distribution decision, not an infra one, and
  # should be made deliberately per product rather than inherited from here.
  bot_zones = { for k, v in local.archived_zones : k => v.zone_id }

  # Zones with edge redirects. See redirects.tf — these are answered by
  # Cloudflare and never reach an origin, which is why they are free.
  #
  # Only mastersbound today. `uni.geniusjnr.com -> mastersbound.com` belongs here
  # too and is deliberately absent: it must not exist until the new host is
  # verified serving 200, and the Android fleet's Remote Config push is gated
  # behind it. Adding it early makes the old host unreachable for every install
  # that has not yet fetched a new config.
  redirect_zones = {
    mastersbound = {
      zone_id = local.active_zones.mastersbound.zone_id
      rules = [
        {
          # `http.host eq` rather than a path match: this fires for every request
          # to the www name, including the root, so no deep link is stranded.
          expression  = "http.host eq \"www.mastersbound.com\""
          description = "www -> apex (canonical host)"
          target      = "concat(\"https://mastersbound.com\", http.request.uri.path)"
        },
      ]
    }
  }

  # Extensions exempted from rate limiting. A single page view pulls dozens of
  # these; counting them would throttle real users long before any crawler.
  #
  # `.json` joined the list with mastersbound.com, and for exactly the stated
  # reason rather than for tidiness. That app's catalogue IS json served as static
  # files — boot alone fetches four (`data/current.json`, `index.json`,
  # `universities.json`, `countries.json`) and then one more per programme opened.
  # At 20 non-static requests per 10s per IP per colo, a person browsing quickly
  # gets blocked for 10 seconds, and the audience makes that worse rather than
  # theoretical: international students behind campus wifi, cafés and
  # carrier-grade NAT arrive as one shared IP.
  #
  # It costs almost nothing to exempt. Those files sit behind the 300s
  # cache-everything rule in cache-rules.tf, so a scraper pulling the whole
  # catalogue is absorbed at the edge and never reaches the origin — the rate
  # limiter was never what protected them.
  #
  # The endpoint that actually needs throttling is unaffected: `/api/v1/...` does
  # not end in `.json`, so it stays counted.
  static_extensions = [
    ".css", ".js", ".png", ".jpg", ".jpeg", ".gif",
    ".svg", ".ico", ".woff", ".woff2", ".webp", ".map", ".json",
  ]

  static_asset_expression = format(
    "not (%s)",
    join(" or ", [
      for e in local.static_extensions :
      format("ends_with(http.request.uri.path, %q)", e)
    ])
  )
}
