# ─── Cross-variable Checks ────────────────────────────────────────────────────
#
# Terraform variable validations cannot reference other variables, so the
# domain/certificate relationships are enforced here with check blocks.
# Failures surface at plan time as clear messages.

check "route53_zone_requires_domain" {
  assert {
    condition     = var.route53_zone_name == "" || var.domain_name != ""
    error_message = "domain_name must be set when route53_zone_name is set - there is nothing to create records for otherwise."
  }
}

check "sans_require_domain" {
  assert {
    condition     = length(var.subject_alternative_names) == 0 || var.domain_name != ""
    error_message = "domain_name must be set when subject_alternative_names is non-empty; the SANs are ignored without it."
  }
}

check "sans_exclude_apex_domain" {
  assert {
    condition     = !contains(var.subject_alternative_names, var.domain_name)
    error_message = "domain_name must not be repeated in subject_alternative_names - ACM rejects a duplicate name on the certificate."
  }
}

# force_destroy lets `terraform destroy` empty and delete the site bucket. That
# is convenient in dev and a foot-gun in prod, where the bucket holds the only
# copy of the deployed site.
check "prod_protects_bucket" {
  assert {
    condition     = var.environment != "prod" || !var.force_destroy
    error_message = "force_destroy must be false when environment = prod."
  }
}
