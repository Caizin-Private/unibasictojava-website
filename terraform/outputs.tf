output "site_bucket_name" {
  description = "Bucket that holds the built site. Sync your dist/ folder here."
  value       = module.site_bucket.s3_bucket_id
}

output "cloudfront_distribution_id" {
  description = "Distribution id, needed to create cache invalidations after a deploy."
  value       = module.cloudfront.cloudfront_distribution_id
}

output "cloudfront_domain_name" {
  description = "Default CloudFront hostname. Always works, even before DNS is wired up."
  value       = module.cloudfront.cloudfront_distribution_domain_name
}

output "site_url" {
  description = "The URL to open once the distribution has deployed."
  value       = local.use_custom_domain ? "https://${var.domain_name}" : "https://${module.cloudfront.cloudfront_distribution_domain_name}"
}

output "acm_certificate_arn" {
  description = "Certificate attached to the distribution."
  value       = local.use_custom_domain ? module.acm.acm_certificate_arn : null
}

output "acm_validation_records" {
  description = "DNS records proving domain ownership. Create these by hand when the zone is not in Route 53; Terraform writes them for you when it is. Empty while no custom domain is configured."
  value       = try(module.acm.validation_domains, [])
}
