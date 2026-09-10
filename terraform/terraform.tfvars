# No custom domain yet - the site is served on the default *.cloudfront.net URL.
# To attach a domain later, fill in domain_name / route53_zone_name and re-apply.

project_name = "unicode-to-java"
aws_region   = "ap-south-1"

# Left null on purpose: credentials come from the AWS_PROFILE environment
# variable, so the account this deploys to is a shell-level choice rather than
# something committed to the repo. Works unchanged for a CI OIDC role.
aws_profile = null

domain_name               = ""
subject_alternative_names = []
route53_zone_name         = ""

# true  -> 403/404 rewritten to /index.html with a 200 (React, Vue, Angular)
# false -> real 404s stay 404s (Hugo, Astro, plain HTML)
spa_mode = true

price_class    = "PriceClass_100"
enable_logging = false
force_destroy  = true
