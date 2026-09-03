# __generated__ by Terraform
# Please review these resources and move them into your main configuration files.
#
# ─────────────────────────────────────────────────────────────────────────────
# HAND EDITS SINCE GENERATION — do not regenerate over these.
#
# 2026-09-03  price_class: PriceClass_All -> PriceClass_100 on six distributions
#             (supertravelr, visa.supertravelr, trips.supertravelr, geniusjnr,
#             contents.geniusjnr, practise.geniusjnr).
#
#   PriceClass_All buys CloudFront's most expensive edge locations — South
#   America, Australia, and the rest of the premium tiers. Every distribution
#   created by the app stacks already pins PriceClass_100; these six predate
#   that rule and were the only ones left on the default.
#
#   It is invisible to real users because Cloudflare is in front of all six:
#   the visitor terminates at a Cloudflare PoP regardless, and CloudFront is
#   only ever the origin behind it. The edge location CloudFront would have
#   used is not part of anyone's experience.
#
#   August's bill contained $2.08 of South-Africa requests and $0.12 of Japan
#   at premium rates, all of it crawler traffic with no user behind it.
#
# 2026-09-03  lifecycle { ignore_changes = [enabled] } on the five distributions
#             the cost circuit breaker is allowed to disable.
#
#   THIS IS A DELIBERATE, NARROW CARVE-OUT FROM "EVERYTHING THROUGH TERRAFORM".
#
#   ../terraform/09-circuit-breaker.tf runs a Lambda that sets Enabled=false on
#   one of these distributions when its CloudWatch alarm fires — the only cost
#   control in this account that acts without a human reading an email, and the
#   reason the abandoned distributions can safely be left running while the
#   Cloudflare edge fix is measured.
#
#   Without ignore_changes, the next `terraform apply` would set Enabled back to
#   true — re-opening the tap in the middle of the incident the breaker just
#   closed, and doing it silently.
#
#   The shape is the same as the SSM secret-value exception already used in this
#   workspace: TERRAFORM OWNS THE RESOURCE, the breaker owns ONE FIELD. Nothing
#   else about these distributions is exempt.
#
#   TO RE-ENABLE A TRIPPED DISTRIBUTION: work out why it tripped first. Then
#   remove `enabled` from that resource's ignore_changes, apply, and put it back.
#   The friction is intentional — coming back up should be a decision.
# ─────────────────────────────────────────────────────────────────────────────

# __generated__ by Terraform from "E3EUOC1VMPIE8D"
resource "aws_cloudfront_distribution" "cf_suprhealthe_com" {
  aliases                         = ["*.suprhealthe.com", "suprhealthe.com"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "web.suprhealthe.com.production.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "allow-all"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "web.suprhealthe.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "web.suprhealthe.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/7d33d895-f66b-4790-bfbe-33c2860aa72d"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "E3DREC6GKO0ZHN"
resource "aws_cloudfront_distribution" "cf_supertravelr_com" {

  # Owned by the cost circuit breaker, not by Terraform. See the carve-out
  # note in this file's header and ../terraform/09-circuit-breaker.tf.
  lifecycle {
    ignore_changes = [enabled]
  }
  aliases                         = ["*.supertravelr.com", "supertravelr.com"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100" # was PriceClass_All — see file header
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  custom_error_response {
    error_caching_min_ttl = 10
    error_code            = 404
    response_code         = 200
    response_page_path    = "/"
  }
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = "19a768b1-44d6-4b5e-8a75-a15b55a1f714"
    smooth_streaming           = false
    target_origin_id           = "S3-Website-web.supertravellr.com.production.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "allow-all"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "web.supertravellr.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "S3-Website-web.supertravellr.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/cf0bab96-3679-4361-9ca7-c9446ad71d40"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "EGE1BE7J30U8P"
resource "aws_cloudfront_distribution" "cf_maxinterview_com" {

  # Owned by the cost circuit breaker, not by Terraform. See the carve-out
  # note in this file's header and ../terraform/09-circuit-breaker.tf.
  lifecycle {
    ignore_changes = [enabled]
  }
  aliases                         = ["*.maxinterview.com", "maxinterview.com"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  custom_error_response {
    error_caching_min_ttl = 10
    error_code            = 404
    response_code         = 200
    response_page_path    = "/"
  }
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "S3-Website-web.maxinterview.com.production.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "redirect-to-https"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "web.maxinterview.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "S3-Website-web.maxinterview.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/15aedeec-578b-4820-9953-e4c92c1abd99"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2019"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "E2EHHD8FZYQM4Z"
resource "aws_cloudfront_distribution" "cf_visa_supertravelr_com" {
  aliases                         = ["visa.supertravelr.com"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100" # was PriceClass_All — see file header
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "visa.supertravelr.com.production.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "allow-all"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "visa.supertravelr.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "visa.supertravelr.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/cf0bab96-3679-4361-9ca7-c9446ad71d40"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "E3LY25D0RHQHYG"
resource "aws_cloudfront_distribution" "cf_contents_dailyapp_cc" {
  aliases                         = ["contents.dailyapp.cc"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "S3-contents.dailyapp.co"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "redirect-to-https"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "contents.dailyapp.co.s3.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "S3-contents.dailyapp.co"
    origin_path              = null
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/0a0849ba-e174-42ec-b7bf-4b3fd6731712"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2019"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "E24NYF7YFMYPJZ"
resource "aws_cloudfront_distribution" "cf_superwomn_com" {
  aliases                         = ["*.superwomn.com", "superwomn.com"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "web.superwomn.com.production.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "allow-all"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "web.superwomn.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "web.superwomn.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/182bf7d1-50f8-4009-bc3c-ef5d2db1d69f"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "E9834VVALEIQC"
resource "aws_cloudfront_distribution" "cf_geniusjnr_com" {

  # Owned by the cost circuit breaker, not by Terraform. See the carve-out
  # note in this file's header and ../terraform/09-circuit-breaker.tf.
  lifecycle {
    ignore_changes = [enabled]
  }
  aliases                         = ["*.geniusjnr.com", "geniusjnr.com"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100" # was PriceClass_All — see file header
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  custom_error_response {
    error_caching_min_ttl = 10
    error_code            = 404
    response_code         = 200
    response_page_path    = "/"
  }
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "S3-Website-web.geniusjnr.com.production.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "redirect-to-https"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "web.geniusjnr.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "S3-Website-web.geniusjnr.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/80652e60-d50e-4909-974d-21edfbc3cbe4"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2019"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "E183U7A1HR01X0"
resource "aws_cloudfront_distribution" "cf_admin_dailyapp_cc" {
  aliases                         = ["admin.dailyapp.cc"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  custom_error_response {
    error_caching_min_ttl = 60
    error_code            = 404
    response_code         = 200
    response_page_path    = "/"
  }
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "S3-Website-admin.dailyapp.co.production.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "redirect-to-https"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "admin.dailyapp.co.production.s3-website.ap-south-1.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "S3-Website-admin.dailyapp.co.production.s3-website.ap-south-1.amazonaws.com"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/0a0849ba-e174-42ec-b7bf-4b3fd6731712"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2019"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "E24BJHZNQCQO33"
resource "aws_cloudfront_distribution" "cf_trips_supertravelr_com" {

  # Owned by the cost circuit breaker, not by Terraform. See the carve-out
  # note in this file's header and ../terraform/09-circuit-breaker.tf.
  lifecycle {
    ignore_changes = [enabled]
  }
  aliases                         = ["trips.supertravelr.com"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100" # was PriceClass_All — see file header
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = "19a768b1-44d6-4b5e-8a75-a15b55a1f714"
    smooth_streaming           = false
    target_origin_id           = "trips.supertravelr.com.production.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "allow-all"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "trips.supertravelr.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "trips.supertravelr.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/cf0bab96-3679-4361-9ca7-c9446ad71d40"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "E3LOSYE99VNG9W"
resource "aws_cloudfront_distribution" "cf_contents_suprhealthe_com" {
  aliases                         = ["contents.suprhealthe.com"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  default_cache_behavior {
    allowed_methods            = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "contents.suprhealthe.com.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "allow-all"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "contents.suprhealthe.com.s3-website.ap-south-1.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "contents.suprhealthe.com.s3-website.ap-south-1.amazonaws.com"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/7d33d895-f66b-4790-bfbe-33c2860aa72d"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "E3I1B4VDUN8RDK"
resource "aws_cloudfront_distribution" "cf_indiabackpacks_com" {
  aliases                         = ["*.indiabackpacks.com", "indiabackpacks.com"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  custom_error_response {
    error_caching_min_ttl = 10
    error_code            = 404
    response_code         = 200
    response_page_path    = "/"
  }
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "S3-Website-web.nirlendu.com.production.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "redirect-to-https"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "web.indiabackpacks.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "S3-Website-web.nirlendu.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/cfc63882-0326-411a-a07d-39a57bf403e0"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2019"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "E3ULDEZ3T0X96V"
resource "aws_cloudfront_distribution" "cf_e3uldez3t0x96v" {
  aliases                         = []
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "S3-contents.indiabackpacks.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "allow-all"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "contents.indiabackpacks.com.s3.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "S3-contents.indiabackpacks.com"
    origin_path              = null
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/cfc63882-0326-411a-a07d-39a57bf403e0"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2019"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "EPM6ZGYBNYP2E"
resource "aws_cloudfront_distribution" "cf_epm6zgybnyp2e" {
  aliases                         = []
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id            = null
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 86400
    field_level_encryption_id  = null
    max_ttl                    = 31536000
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "S3-app.masterclub.videos"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "redirect-to-https"
    forwarded_values {
      headers                 = []
      query_string            = false
      query_string_cache_keys = []
      cookies {
        forward           = "none"
        whitelisted_names = []
      }
    }
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "app.masterclub.videos.s3.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "S3-app.masterclub.videos"
    origin_path              = null
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = null
    cloudfront_default_certificate = true
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1"
    ssl_support_method             = null
  }
}

# __generated__ by Terraform from "E2EPMLL5YZ9R6M"
resource "aws_cloudfront_distribution" "cf_contents_geniusjnr_com" {
  aliases                         = ["contents.geniusjnr.com"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100" # was PriceClass_All — see file header
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "learn.geniusjnr.com.production.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "allow-all"
    grpc_config {
      enabled = false
    }
  }
  ordered_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    path_pattern               = "/*"
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "learn.geniusjnr.com.production.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "allow-all"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "learn.geniusjnr.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "learn.geniusjnr.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/80652e60-d50e-4909-974d-21edfbc3cbe4"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "E1BG16F7OLWNO3"
resource "aws_cloudfront_distribution" "cf_e1bg16f7olwno3" {
  aliases                         = []
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "S3-contents.maxinterview.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "allow-all"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "contents.maxinterview.com.s3.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "S3-contents.maxinterview.com"
    origin_path              = null
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/15aedeec-578b-4820-9953-e4c92c1abd99"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2019"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "E23IHIABKH8IY8"
resource "aws_cloudfront_distribution" "cf_dailyapp_cc" {
  aliases                         = ["*.dailyapp.cc", "dailyapp.cc"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  custom_error_response {
    error_caching_min_ttl = 60
    error_code            = 404
    response_code         = 200
    response_page_path    = "/"
  }
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "S3-Website-web.dailyapp.co.production.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "redirect-to-https"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "web.dailyapp.co.production.s3-website.ap-south-1.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "S3-Website-web.dailyapp.co.production.s3-website.ap-south-1.amazonaws.com"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/0a0849ba-e174-42ec-b7bf-4b3fd6731712"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2019"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "EUKZ2DCOYH9LU"
resource "aws_cloudfront_distribution" "cf_bettermoney_in" {
  aliases                         = ["*.bettermoney.in", "bettermoney.in"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  custom_error_response {
    error_caching_min_ttl = 10
    error_code            = 404
    response_code         = 200
    response_page_path    = "/"
  }
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "S3-Website-web.bettermoney.in.production.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "redirect-to-https"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "web.bettermoney.in.production.s3-website.ap-south-1.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "S3-Website-web.bettermoney.in.production.s3-website.ap-south-1.amazonaws.com"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/bcb01d4b-04db-4990-9524-1f4bbbafef0c"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2019"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "ETX7NAHEKHMR"
resource "aws_cloudfront_distribution" "cf_code_maxinterview_com" {

  # Owned by the cost circuit breaker, not by Terraform. See the carve-out
  # note in this file's header and ../terraform/09-circuit-breaker.tf.
  lifecycle {
    ignore_changes = [enabled]
  }
  aliases                         = ["code.maxinterview.com"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "contents.maxinterview.com.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "allow-all"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "contents.maxinterview.com.s3-website.ap-south-1.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "contents.maxinterview.com.s3-website.ap-south-1.amazonaws.com"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/15aedeec-578b-4820-9953-e4c92c1abd99"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "E34ZUD3UTWYZBJ"
resource "aws_cloudfront_distribution" "cf_assets_maxinterview_com" {
  aliases                         = ["assets.maxinterview.com"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = null
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 86400
    field_level_encryption_id  = null
    max_ttl                    = 31536000
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "S3-maxinterview-prod"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "allow-all"
    forwarded_values {
      headers                 = []
      query_string            = false
      query_string_cache_keys = []
      cookies {
        forward           = "none"
        whitelisted_names = []
      }
    }
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "maxinterview-prod.s3.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "S3-maxinterview-prod"
    origin_path              = null
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = null
    cloudfront_default_certificate = true
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1"
    ssl_support_method             = null
  }
}

# __generated__ by Terraform from "EOX4UDWXBJL7S"
resource "aws_cloudfront_distribution" "cf_eox4udwxbjl7s" {
  aliases                         = []
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id            = null
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 86400
    field_level_encryption_id  = null
    max_ttl                    = 31536000
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "S3-app.masterclub.contents"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "redirect-to-https"
    forwarded_values {
      headers                 = []
      query_string            = false
      query_string_cache_keys = []
      cookies {
        forward           = "none"
        whitelisted_names = []
      }
    }
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "app.masterclub.contents.s3.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "S3-app.masterclub.contents"
    origin_path              = null
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = null
    cloudfront_default_certificate = true
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1"
    ssl_support_method             = null
  }
}

# __generated__ by Terraform from "E2YM8CY1KTELFJ"
resource "aws_cloudfront_distribution" "cf_masterclub_app" {
  aliases                         = ["*.masterclub.app", "masterclub.app"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = "/index.html"
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  custom_error_response {
    error_caching_min_ttl = 300
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
  }
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id            = null
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 86400
    field_level_encryption_id  = null
    max_ttl                    = 31536000
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "S3-Website-app.masterclub.web.assets.production.s3-website-us-west-2.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "redirect-to-https"
    forwarded_values {
      headers                 = []
      query_string            = false
      query_string_cache_keys = []
      cookies {
        forward           = "none"
        whitelisted_names = []
      }
    }
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "app.masterclub.web.assets.production.s3-website-us-west-2.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "S3-Website-app.masterclub.web.assets.production.s3-website-us-west-2.amazonaws.com"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = null
    cloudfront_default_certificate = true
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1"
    ssl_support_method             = null
  }
}

# __generated__ by Terraform from "E3BM5I3EG6OBC9"
resource "aws_cloudfront_distribution" "cf_contents_maxinterview_com" {
  aliases                         = ["contents.maxinterview.com"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = "index.html"
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "in.maxinterview.com.production.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "allow-all"
    grpc_config {
      enabled = false
    }
  }
  ordered_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    path_pattern               = "/*"
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "in.maxinterview.com.production.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "allow-all"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "in.maxinterview.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "in.maxinterview.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/15aedeec-578b-4820-9953-e4c92c1abd99"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "EL303CN2OP85W"
resource "aws_cloudfront_distribution" "cf_nirlendu_com" {
  aliases                         = ["*.nirlendu.com", "nirlendu.com"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  custom_error_response {
    error_caching_min_ttl = 10
    error_code            = 404
    response_code         = 200
    response_page_path    = "/"
  }
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "S3-web.nirlendu.com.production"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "redirect-to-https"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "web.nirlendu.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "S3-web.nirlendu.com.production"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/523f8d17-66ef-4dd9-b862-8f786b0e689b"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2019"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "EFGNU19TOBWN9"
resource "aws_cloudfront_distribution" "cf_plusfoods_in" {
  aliases                         = ["*.plusfoods.in", "plusfoods.in"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100"
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  custom_error_response {
    error_caching_min_ttl = 10
    error_code            = 404
    response_code         = 200
    response_page_path    = "/"
  }
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "S3-Website-web.plusfoods.in.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "redirect-to-https"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "web.plusfoods.in.s3-website.ap-south-1.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "S3-Website-web.plusfoods.in.s3-website.ap-south-1.amazonaws.com"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/c5ac820a-8aa3-4bc8-892c-1c93c6ac6169"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2019"
    ssl_support_method             = "sni-only"
  }
}

# __generated__ by Terraform from "EK8CHAKDC7UH0"
resource "aws_cloudfront_distribution" "cf_practise_geniusjnr_com" {
  aliases                         = ["practise.geniusjnr.com"]
  comment                         = null
  continuous_deployment_policy_id = null
  default_root_object             = null
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_100" # was PriceClass_All — see file header
  retain_on_delete                = false
  staging                         = false
  tags                            = {}
  tags_all                        = {}
  wait_for_deployment             = true
  web_acl_id                      = null
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "practise.geniusjnr.com.production.s3-website.ap-south-1.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "allow-all"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "practise.geniusjnr.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_access_control_id = null
    origin_id                = "practise.geniusjnr.com.production.s3-website.ap-south-1.amazonaws.com"
    origin_path              = null
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:419105693501:certificate/80652e60-d50e-4909-974d-21edfbc3cbe4"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }
}
