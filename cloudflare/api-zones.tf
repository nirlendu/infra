###############################################################################
# EDGE SECURITY FOR ZONES WHOSE PRODUCT IS AN API
#
# WHY THIS FILE EXISTS AT ALL, given that zones.tf puts authoxi in
# `topology_only_zones` and says product zones get topology and nothing else.
#
# That rule is about CACHING, and it is right: a cache rule on an API Gateway
# origin can serve one tenant's response to another, so cache policy belongs to
# the app stack that knows what is tenant-scoped. Edge SECURITY is a third
# category — neither caching nor topology — and it cannot live in the app stack
# for a concrete reason: the Cloudflare token is an account-wide bearer
# credential that can repoint DNS for every domain the account holds
# (../terraform/06-cloudflare-token.tf says so in as many words). Wiring it
# into authoxi's stack, and into authoxi's CI, would spread that credential to
# reach one hostname. It stays here, where it already is.
#
# ── WHAT WENT WRONG, 2026-09-10 ───────────────────────────────────────────────
#
# agitome could not authenticate ANY tenant in production. Every authenticated
# route returned 503 `accounts_unavailable`. agitome is a relying party: it
# validates every key by calling authoxi's Accounts plane, and that call was
# being answered by Cloudflare rather than by authoxi:
#
#   STATUS 403 · cf-mitigated: challenge · server: cloudflare
#   <title>Just a moment...</title> … challenges.cloudflare.com
#
# A managed challenge. An HTTP client cannot solve one, so it saw a 403 with an
# HTML body and reported "authoxi rejected our service credential" — which was
# false, and the credential was fine. The same request from a laptop returned
# 200 with identical headers, so the differentiator was the SOURCE IP: an ECS
# task on an AWS range.
#
# Neither setting causing it was declared anywhere. `fight_mode` and
# `browser_check` were on for this zone through the dashboard, and no
# repository described them. This is exactly the drift the workspace's
# Terraform rule exists to prevent, and it is why the fix is declared here
# rather than clicked back off.
#
# ── WHY BOT FIGHT MODE IS WRONG ON THIS ZONE SPECIFICALLY ────────────────────
#
# Not merely inconvenient — self-defeating. authoxi's product IS agent
# identity: it exists to authenticate automated clients, its robots.txt
# explicitly admits GPTBot, ClaudeBot, OAI-SearchBot and Claude-User, and its
# SDKs are machine callers by construction. Bot Fight Mode challenges exactly
# the traffic the product is for. Every pillar resolves tenancy through this
# hostname, so agentlox and agiremit would have hit the identical wall the
# first time either called it from a task.
#
# Bot Fight Mode is zone-wide on the Free plan — it cannot be scoped to a
# hostname and it cannot be skipped by a custom rule, because it runs before
# them. So it goes off for the zone, and the narrower controls below carry the
# protection that is still wanted.
###############################################################################

locals {
  # Zones whose PRIMARY hostname serves machines. Kept as a map rather than a
  # single zone id because agitome, agentlox and agiremit each publish an
  # `api.` hostname on the same pattern and will need the same treatment; the
  # second one added should not be a copy-paste of this file.
  #
  # agitome is NOT here yet. It has the same shape and probably the same
  # latent bug, but nothing has been observed failing against it, and turning
  # off a live protection on evidence that has not been gathered is how the
  # next incident starts.
  api_zones = {
    authoxi = local.topology_only_zones.authoxi.zone_id
  }

  # The hostname that must never be challenged, per zone. The apex and www keep
  # every protection: they serve a console and a landing page to people.
  api_hostnames = {
    authoxi = "api.authoxi.com"
  }
}

# ── Bot Fight Mode off; AI-crawler protection stays off too ───────────────────
#
# `ai_bots_protection` is left "disabled" deliberately and is NOT the same
# decision as bot-management.tf makes for the archived zones. There it blocks
# AI training crawlers on abandoned marketing sites, where crawling is pure
# cost. Here the product WANTS to be readable by agents — that is the entire
# GTM position — so blocking them would contradict the robots.txt the app
# serves.
#
# GOTCHA carried over from bot-management.tf: the API rejects fight_mode=true
# unless enable_js is also true. Turning fight_mode OFF, enable_js may follow.
resource "cloudflare_bot_management" "api" {
  for_each = local.api_zones

  zone_id = each.value

  enable_js          = false
  fight_mode         = false
  ai_bots_protection = "disabled"
}

# ── Browser Integrity Check skipped on the API hostname only ──────────────────
#
# BIC challenges requests whose headers do not look like a browser's. Every SDK
# call is such a request. It was probably not the trigger on 2026-09-10 — an
# identical httpx call from a laptop was let through, so the decision was made
# on IP rather than headers — but it is a challenge that a machine API can trip
# at any time, and leaving it armed here means fixing this twice.
#
# `skip` with products = ["bic"] is surgical: it turns off one product for one
# hostname and leaves the managed WAF ruleset, DDoS protection and everything
# on the apex untouched.
resource "cloudflare_ruleset" "api_security" {
  for_each = local.api_zones

  zone_id = each.value
  # Cloudflare names every phase-entrypoint ruleset "default" and will not
  # accept another value without replacing the ruleset — the same constraint
  # documented in cache-rules.tf, waf-rules.tf and rate-limits.tf.
  name  = "default"
  kind  = "zone"
  phase = "http_request_firewall_custom"

  rules = [
    {
      action = "skip"
      action_parameters = {
        products = ["bic"]
      }
      expression  = "(http.host eq \"${local.api_hostnames[each.key]}\")"
      description = "Machine API: skip Browser Integrity Check (no client can solve a challenge)"
      enabled     = true
    },
  ]
}
