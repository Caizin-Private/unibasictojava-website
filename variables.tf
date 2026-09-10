variable "project" {
  description = "Project name. Combined with environment to prefix resource names and tags."
  type        = string
}

variable "environment" {
  description = "Environment name, e.g. prod. Combined with project to prefix resource names and tags."
  type        = string
}

variable "owner" {
  description = "Team accountable for these resources. Applied as the Owner tag."
  type        = string
}

variable "cost_center" {
  description = "Billing attribution. Applied as the CostCenter tag."
  type        = string
}

variable "aws_region" {
  description = "Region for the S3 bucket. CloudFront is global; the ACM cert is always created in us-east-1."
  type        = string
}

variable "domain_name" {
  description = "Apex domain for the site, e.g. example.com. Leave empty to deploy on the default *.cloudfront.net URL with no custom domain."
  type        = string
  default     = ""
}

variable "subject_alternative_names" {
  description = "Extra names on the certificate and distribution, e.g. [\"www.example.com\"]. Ignored when domain_name is empty."
  type        = list(string)
  default     = []
}

variable "route53_zone_name" {
  description = "Hosted zone that owns domain_name, e.g. example.com. Leave empty if DNS is managed outside Route 53 - you will then create the validation and alias records by hand."
  type        = string
  default     = ""
}

variable "spa_mode" {
  description = "Map 403/404 responses to /index.html with a 200 so client-side routers work. Set false for a multi-page static site where real 404s should stay 404s."
  type        = bool
  default     = true
}

variable "price_class" {
  description = "PriceClass_100 (NA + EU), PriceClass_200 (adds Asia), or PriceClass_All."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

variable "enable_logging" {
  description = "Ship CloudFront standard access logs to a dedicated bucket."
  type        = bool
  default     = false
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete a non-empty site bucket. Handy for dev, dangerous for prod."
  type        = bool
  default     = false
}
