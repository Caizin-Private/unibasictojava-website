provider "aws" {
  region = var.aws_region

  # Common tags applied automatically to all resources via the AWS provider.
  # Credentials come from the standard chain - set AWS_PROFILE in the shell.
  default_tags {
    tags = local.common_tags
  }
}

# CloudFront only reads ACM certificates from us-east-1, regardless of where the
# bucket lives. This aliased provider exists solely for the certificate.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}
