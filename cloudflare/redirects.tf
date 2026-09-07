###############################################################################
# Edge redirects — answered by Cloudflare, never forwarded to an origin.
#
# A redirect is the cheapest possible response: it never reaches CloudFront, so
# it never bills, and the visitor is answered from the data centre they are
# already talking to. Single Redirects are on the Free plan.
#
# WHY THIS IS NOT A DISTRIBUTION ALIAS. The obvious way to serve
# `www.mastersbound.com` is to add it to `aliases` in the app's cdn.tf, and the
# wildcard on that certificate already covers it. That would work and it would be
# worse: two hostnames serving identical HTML is a duplicate-content split for
# crawlers, and it doubles the surface that has to stay in sync. One canonical
# host, everything else redirected, is the shape worth keeping.
###############################################################################

resource "cloudflare_ruleset" "redirects" {
  for_each = local.redirect_zones

  zone_id = each.value.zone_id
  # Cloudflare names every phase-ENTRYPOINT ruleset "default" and will not accept
  # another value without replacing the ruleset — the same constraint recorded in
  # cache-rules.tf and rate-limits.tf. The terraform resource name carries the
  # meaning instead.
  name  = "default"
  kind  = "zone"
  phase = "http_request_dynamic_redirect"

  rules = [
    for r in each.value.rules : {
      action      = "redirect"
      expression  = r.expression
      description = r.description
      enabled     = true

      action_parameters = {
        from_value = {
          # 301, not 302. These are permanent facts about where the site lives,
          # and a 301 is the only version a search engine consolidates ranking
          # through. A 302 leaves both URLs indexed indefinitely.
          status_code = 301

          target_url = {
            expression = r.target
          }

          # Carry the path and query across. Without this every redirect lands on
          # the home page, which silently breaks deep links, shared URLs and every
          # crawler's existing index of the old host.
          preserve_query_string = true
        }
      }
    }
  ]
}
