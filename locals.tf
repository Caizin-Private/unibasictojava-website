locals {
  name_prefix = "${var.project}-${var.environment}"

  # Applied to all resources via provider default_tags.
  common_tags = {
    Environment = var.environment
    Project     = var.project
    Owner       = var.owner
    CostCenter  = var.cost_center
    ManagedBy   = "terraform"
    Repo        = "github.com/Caizin-Private/unibasictojava-website"
  }

  use_custom_domain = var.domain_name != ""
  use_route53       = local.use_custom_domain && var.route53_zone_name != ""

  aliases = local.use_custom_domain ? concat([var.domain_name], var.subject_alternative_names) : null

  # Bucket names are globally unique across all of AWS, so the account id is
  # appended to keep the same config working in more than one account.
  site_bucket_name = "${local.name_prefix}-site-${data.aws_caller_identity.current.account_id}"
  logs_bucket_name = "${local.name_prefix}-cdn-logs-${data.aws_caller_identity.current.account_id}"

  origin_id = "s3-site"

  # A SPA serves index.html for any unknown path so the client-side router can
  # handle it. A multi-page site must let real 404s surface as 404s.
  custom_error_response = var.spa_mode ? [
    {
      error_code            = 403
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 10
    },
    {
      error_code            = 404
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 10
    },
  ] : null
}
