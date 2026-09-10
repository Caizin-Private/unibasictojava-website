data "aws_caller_identity" "current" {}

data "aws_route53_zone" "this" {
  count = local.use_route53 ? 1 : 0

  name         = var.route53_zone_name
  private_zone = false
}

# AWS-managed policies. Referencing them by name keeps the config readable and
# lets AWS maintain the underlying cache-key and header definitions.
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
}

################################################################################
# S3 - private origin bucket
################################################################################

module "site_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.15"

  bucket        = local.site_bucket_name
  force_destroy = var.force_destroy

  # Static website hosting stays OFF. CloudFront reaches the bucket over its
  # REST endpoint via OAC, so the bucket never needs to be public.
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
}

module "logs_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.15"

  create_bucket = var.enable_logging

  bucket        = local.logs_bucket_name
  force_destroy = var.force_destroy

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # CloudFront standard logging delivers via ACL, so this bucket cannot use
  # BucketOwnerEnforced the way the site bucket does.
  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  lifecycle_rule = [
    {
      id     = "expire-old-logs"
      status = "Enabled"

      expiration = {
        days = 90
      }
    }
  ]
}

################################################################################
# ACM - certificate must live in us-east-1 for CloudFront
################################################################################

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 6.3"

  providers = {
    aws = aws.us_east_1
  }

  create_certificate = local.use_custom_domain

  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  zone_id = local.use_route53 ? data.aws_route53_zone.this[0].zone_id : null

  # Without a Route 53 zone we cannot write the validation records, so the
  # certificate is created and left pending for manual validation.
  create_route53_records = local.use_route53
  validate_certificate   = local.use_route53
  wait_for_validation    = local.use_route53
}

################################################################################
# CloudFront
################################################################################

module "cloudfront" {
  source  = "terraform-aws-modules/cloudfront/aws"
  version = "~> 6.7"

  comment             = "${local.name_prefix} static site"
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = var.price_class
  retain_on_delete    = false
  wait_for_deployment = false
  default_root_object = "index.html"

  aliases = local.aliases

  origin_access_control = {
    s3 = {
      description      = "CloudFront access to the ${local.site_bucket_name} bucket"
      origin_type      = "s3"
      signing_behavior = "always"
      signing_protocol = "sigv4"
    }
  }

  origin = {
    (local.origin_id) = {
      domain_name               = module.site_bucket.s3_bucket_bucket_regional_domain_name
      origin_access_control_key = "s3"
    }
  }

  default_cache_behavior = {
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true

    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
  }

  # The HTML entrypoint must not be cached at the edge, otherwise a deploy keeps
  # serving the old bundle references until the TTL expires.
  ordered_cache_behavior = [
    {
      path_pattern           = "/index.html"
      target_origin_id       = local.origin_id
      viewer_protocol_policy = "redirect-to-https"

      allowed_methods = ["GET", "HEAD", "OPTIONS"]
      cached_methods  = ["GET", "HEAD"]
      compress        = true

      cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
      response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
    }
  ]

  custom_error_response = local.custom_error_response

  logging_config = var.enable_logging ? {
    bucket = module.logs_bucket.s3_bucket_bucket_domain_name
    prefix = "cloudfront/"
  } : null

  # Both branches carry the same attribute set. A conditional whose two sides are
  # objects with different attributes fails type unification in Terraform.
  viewer_certificate = local.use_custom_domain ? {
    cloudfront_default_certificate = null
    acm_certificate_arn            = module.acm.acm_certificate_arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
    } : {
    # The default *.cloudfront.net certificate is supplied by AWS. It does not
    # accept ssl_support_method or a minimum protocol version.
    cloudfront_default_certificate = true
    acm_certificate_arn            = null
    ssl_support_method             = null
    minimum_protocol_version       = null
  }
}

################################################################################
# Bucket policy - read access granted to this one distribution only
################################################################################

data "aws_iam_policy_document" "site_bucket" {
  statement {
    sid       = "AllowCloudFrontServicePrincipalReadOnly"
    actions   = ["s3:GetObject"]
    resources = ["${module.site_bucket.s3_bucket_arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [module.cloudfront.cloudfront_distribution_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site_bucket" {
  bucket = module.site_bucket.s3_bucket_id
  policy = data.aws_iam_policy_document.site_bucket.json
}

################################################################################
# Route 53 alias records
################################################################################

resource "aws_route53_record" "ipv4" {
  for_each = local.use_route53 ? toset(local.aliases) : toset([])

  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = module.cloudfront.cloudfront_distribution_domain_name
    zone_id                = module.cloudfront.cloudfront_distribution_hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "ipv6" {
  for_each = local.use_route53 ? toset(local.aliases) : toset([])

  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = each.value
  type    = "AAAA"

  alias {
    name                   = module.cloudfront.cloudfront_distribution_domain_name
    zone_id                = module.cloudfront.cloudfront_distribution_hosted_zone_id
    evaluate_target_health = false
  }
}
