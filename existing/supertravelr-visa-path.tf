###############################################################################
# supertravelr.com/visa -> the supertravelr-visa web bucket.
#
# HAND-WRITTEN, unlike generated_cloudfront.tf next to it. These resources are
# new, not imported, and they exist to hang a second app off a distribution that
# already serves a different one.
#
# ── Why the app does not get its own distribution ────────────────────────────
# CloudFront allows an alias on exactly ONE distribution. E3DREC6GKO0ZHN has held
# `supertravelr.com` and `*.supertravelr.com` since long before this app, so a
# second distribution claiming the hostname fails with CNAMEAlreadyExists, and
# moving the alias to win would take the legacy site down. One distribution per
# hostname, a path behaviour per app, is the only shape that does not fight.
#
# ── What this does NOT touch ─────────────────────────────────────────────────
# The default cache behaviour and the legacy S3-website origin are unchanged. A
# request that is not `/visa/*` follows exactly the path it followed before.
###############################################################################

# The visa app's bucket is hardened — public access blocked, no website endpoint —
# so CloudFront reaches it as a REST origin with a signed request. That is the
# difference from every other origin in this stack, which are public S3 *website*
# endpoints inherited from an older way of doing things.
resource "aws_cloudfront_origin_access_control" "supertravelr_visa_web" {
  name                              = "supertravelr-visa-web-prod"
  description                       = "OAC for the supertravelr-visa static export bucket."
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ── Directory index rewrite ──────────────────────────────────────────────────
#
# The export is built with `trailingSlash: true`, so a page lives at
# `visa/en/dashboard/index.html`. A REST origin has no directory semantics: a
# request for `/visa/en/dashboard/` asks S3 for a key that does not exist and gets
# a 403, not the page. This function is what makes the export navigable.
#
# It is NOT an SPA fallback, deliberately. It rewrites a trailing slash to
# index.html and redirects an extensionless path to its slash form; anything else
# is passed through untouched, so a genuinely missing path stays missing instead
# of silently rendering the app shell with a 200.
resource "aws_cloudfront_function" "supertravelr_visa_index_rewrite" {
  name    = "supertravelr-visa-index-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Directory-index rewrite for the supertravelr-visa static export. Not an SPA fallback."
  publish = true
  code    = <<-JS
    function handler(event) {
      var uri = event.request.uri;

      // `/visa/en/dashboard/` -> `/visa/en/dashboard/index.html`
      if (uri.endsWith('/')) {
        event.request.uri = uri + 'index.html';
        return event.request;
      }

      // A real file (it has an extension) goes straight through.
      var last = uri.split('/').pop();
      if (last.indexOf('.') !== -1) {
        return event.request;
      }

      // `/visa/en/dashboard` -> redirect to the slash form, so there is one
      // canonical URL per page rather than two that both work.
      return {
        statusCode: 301,
        statusDescription: 'Moved Permanently',
        headers: { location: { value: uri + '/' } }
      };
    }
  JS
}
