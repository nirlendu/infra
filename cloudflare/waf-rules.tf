###############################################################################
# WAF custom rules — targeted at crawlers, invisible to people.
#
# The Free plan allows five custom rules per zone. That is enough, because the
# useful rule here is narrow.
#
# WHAT THIS IS FOR, AND WHAT IT IS NOT
#
# Bot Fight Mode and ai_bots_protection are already on for these zones
# (bot-management.tf). They cover declared AI training crawlers and obvious
# automation. What they do not cover is the ordinary scraper that sends a
# browser user-agent from a rented server — which is the shape of most of what
# hit maxinterview.com in August.
#
# The distinguishing fact about that traffic is not its user-agent, which is a
# free-text field anyone can set. It is WHERE IT COMES FROM: real visitors
# browse from residential and mobile networks, and crawlers run in data
# centres. An ASN match is therefore a rule that catches crawlers while being
# invisible to every actual human visitor — which is what keeps it inside the
# "do not touch the legacy apps" constraint.
#
# ORDERING: rules evaluate top-down and the first match wins.
###############################################################################

resource "cloudflare_ruleset" "waf_archived" {
  for_each = local.bot_zones

  zone_id = each.value
  # Cloudflare names every phase-ENTRYPOINT ruleset "default" and will not
  # accept another value without replacing the ruleset — the same constraint
  # documented in cache-rules.tf and rate-limits.tf. The terraform resource
  # name carries the meaning.
  name  = "default"
  kind  = "zone"
  phase = "http_request_firewall_custom"

  rules = [
    # ── 1. Data-centre traffic that is not a verified crawler ───────────────
    #
    # `not cf.client.bot` is doing the important work: Cloudflare maintains the
    # list of VERIFIED crawlers (Googlebot, Bingbot and the rest, validated by
    # reverse DNS rather than by user-agent), and this exempts all of them. SEO
    # is the entire remaining value of these domains, so a rule that could
    # de-index them would be worse than the bill it prevents.
    #
    # What is left after that exemption is traffic from a hosting provider
    # claiming to be a browser. There is no legitimate version of that on an
    # abandoned marketing site.
    #
    # managed_challenge, not block: a challenge costs the crawler far more than
    # it costs us, degrades gracefully if the ASN list is ever wrong, and lets a
    # real person on a VPN through after one interstitial. `block` on a
    # mis-typed ASN is a silent outage on a site nobody is watching.
    {
      action      = "managed_challenge"
      expression  = "(not cf.client.bot) and (ip.geoip.asnum in {16509 14618 15169 8075 14061 16276 24940 20473 45102 132203 63949 51167})"
      description = "Challenge datacenter-ASN traffic that is not a verified crawler"
      enabled     = true
    },

    # ── 2. THE ESCALATION LEVER — deliberately disabled ────────────────────
    #
    # This is the broad version: challenge everything that is not a verified
    # crawler, human visitors included. On an abandoned zone that is defensible
    # — there are no users to inconvenience — and it is the strongest control
    # available on the Free plan short of taking the site offline.
    #
    # It ships DISABLED for two reasons:
    #
    #   1. It is a VISIBLE change. Every visitor sees an interstitial. The
    #      standing instruction is not to change how the legacy apps behave
    #      until the decision to retire them is made.
    #
    #   2. It would confound the measurement. The point of the current change
    #      set is to find out whether tiered caching plus the cache-key fix is
    #      sufficient on its own. Turning this on at the same time means never
    #      learning which one worked.
    #
    # FLIP THIS TO `true` IF: seven days of the per-distribution CloudWatch
    # alarms (../terraform/07-cloudfront-alarms.tf) show origin requests still
    # elevated after the edge changes land. That is the pre-agreed escalation,
    # and it is one boolean rather than new code written under pressure.
    #
    # It is scoped to maxinterview only — the zone responsible for roughly 96%
    # of the abandoned-product traffic. The other archived zones are two orders
    # of magnitude smaller and are not worth a visible change.
    {
      action      = "managed_challenge"
      expression  = "(not cf.client.bot) and (http.host contains \"maxinterview.com\")"
      description = "ESCALATION (disabled): challenge all non-verified-bot traffic"
      enabled     = false
    },
  ]
}
