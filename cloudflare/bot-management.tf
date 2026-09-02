###############################################################################
# Bot protection.
#
# CORRECTING A COMMON ASSUMPTION: Bot Fight Mode was ALREADY ON during the Aug
# 2026 incident. It is not the gap. Bot Fight Mode exempts verified bots, and
# the AI-crawler controls — the ones that actually matter for a content site
# being scraped — shipped defaulted to `only_on_ad_pages`, which on a site with
# no ad pages means off. GPTBot, CCBot, Scrapy and plain python-requests all
# returned HTTP 200 while "bot protection" read as enabled in the dashboard.
#
# So the meaningful setting here is ai_bots_protection = "block". Everything
# else is confirming what was already true.
#
# WHY ARCHIVED ZONES ONLY: blocking AI crawlers is a content-distribution
# decision (does this product want to appear in AI answers?), not an infra one.
# For an abandoned site the answer is obviously "don't pay to be scraped". For
# a live product it is a real product call, so it is made per-product rather
# than inherited from a shared infra file.
#
# `crawler_protection` is deliberately LEFT DISABLED. It risks blocking search
# crawlers, and SEO traffic is the entire remaining value of these domains.
# ai_bots_protection targets AI training crawlers specifically and does not
# affect search indexing.
#
# GOTCHA: the API rejects fight_mode=true unless enable_js is also true
# ("cannot enable Fight_Mode while EnableJS is disabled"). Both must be sent.
###############################################################################

resource "cloudflare_bot_management" "archived" {
  for_each = local.bot_zones

  zone_id = each.value

  enable_js          = true
  fight_mode         = true
  ai_bots_protection = "block"
}
