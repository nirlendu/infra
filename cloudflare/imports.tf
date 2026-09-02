###############################################################################
# Import blocks — adopting the live edge config into state.
#
# These rules were applied by hand during the Aug 2026 CloudFront cost incident
# (2026-09-02) before this stack existed. Importing rather than recreating
# keeps the fix continuously in force: a create-and-replace would drop caching
# for the seconds between destroy and create, on zones that are actively being
# crawled.
#
# Ruleset IDs are per-zone-per-phase and stable once created. Cloudflare
# `cloudflare_ruleset` imports as "<zone_id>/<ruleset_id>";
# `cloudflare_bot_management` imports as just "<zone_id>".
#
# SAFE TO DELETE once `terraform apply` has run once and state is populated.
# Import blocks are declarative no-ops after the resource is in state, so
# leaving them costs nothing but noise.
###############################################################################

# ───── cache rules: archived zones (24h edge TTL) ─────

import {
  to = cloudflare_ruleset.cache_archived["maxinterview"]
  id = "zones/e2450d7f14fdcf30e34212613f7eaa16/ae46cf5868764092946a8206faeb709f"
}

import {
  to = cloudflare_ruleset.cache_archived["nirlendu"]
  id = "zones/50d402d707b43a6717ee06aaf1d79f81/63da59d1d2f74257a51af7ba5aff319a"
}

import {
  to = cloudflare_ruleset.cache_archived["superwomn"]
  id = "zones/b04e6e45e899cf5c6b349964fdc86643/8a62937f097946a394cbfd567beb6335"
}

import {
  to = cloudflare_ruleset.cache_archived["suprhealthe"]
  id = "zones/68de4bb68b0882c0dbc4db705cfc3fc1/c6193f77aa86408cae2d8957920db799"
}

# ───── cache rules: active zones (300s edge TTL + /api bypass) ─────

import {
  to = cloudflare_ruleset.cache_active["geniusjnr"]
  id = "zones/04215cd92c731147fe3cf48f016efc5a/e581d12bba0b4a06a77078c92bea02f9"
}

import {
  to = cloudflare_ruleset.cache_active["supertravelr"]
  id = "zones/26402352e1cd08e18793200675137760/b25a5bfdf560461cba030cd89896dfa0"
}

# ───── rate limits ─────

import {
  to = cloudflare_ruleset.ratelimit["maxinterview"]
  id = "zones/e2450d7f14fdcf30e34212613f7eaa16/bf18ce8ee7314f76b28542efd7beb004"
}

import {
  to = cloudflare_ruleset.ratelimit["geniusjnr"]
  id = "zones/04215cd92c731147fe3cf48f016efc5a/5a960671355e4f7ab3e8c2dc99ec0f24"
}

import {
  to = cloudflare_ruleset.ratelimit["supertravelr"]
  id = "zones/26402352e1cd08e18793200675137760/ac9645e7d9154f89b414c98ad8d4d7a2"
}

# ───── bot management (archived zones) ─────

import {
  to = cloudflare_bot_management.archived["maxinterview"]
  id = "e2450d7f14fdcf30e34212613f7eaa16"
}

import {
  to = cloudflare_bot_management.archived["nirlendu"]
  id = "50d402d707b43a6717ee06aaf1d79f81"
}

import {
  to = cloudflare_bot_management.archived["superwomn"]
  id = "b04e6e45e899cf5c6b349964fdc86643"
}

import {
  to = cloudflare_bot_management.archived["suprhealthe"]
  id = "68de4bb68b0882c0dbc4db705cfc3fc1"
}
