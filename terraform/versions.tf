terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.46"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Null falls back to the standard credential chain (AWS_PROFILE, environment
  # variables, instance role), which is what CI should use.
  profile = var.aws_profile

  default_tags {
    tags = var.tags
  }
}

# CloudFront only reads ACM certificates from us-east-1, regardless of
# where the bucket lives. This aliased provider exists solely for the cert.
provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = var.aws_profile

  default_tags {
    tags = var.tags
  }
}
