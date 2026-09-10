terraform {
  required_version = "~> 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Backend is configured via -backend-config per environment:
  # terraform init -backend-config=environments/<env>/backend.hcl
  backend "s3" {}
}
