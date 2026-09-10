aws_region = "ap-south-1"

project     = "unibasictojava"
environment = "prod"
owner       = "devops"
cost_center = "caizin"

# No custom domain yet - the site is served on the default *.cloudfront.net URL.
# To attach a domain later, fill in domain_name / route53_zone_name and re-apply;
# the distribution, bucket and URL all survive, so nothing needs redeploying.
domain_name               = ""
subject_alternative_names = []
route53_zone_name         = ""

# true  -> 403/404 rewritten to /index.html with a 200 (React, Vue, Angular)
# false -> real 404s stay 404s (Hugo, Astro, plain HTML)
spa_mode = true

price_class    = "PriceClass_100"
enable_logging = false

# checks.tf refuses force_destroy = true while environment = "prod".
force_destroy = false
