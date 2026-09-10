# Terraform remote state — prod environment
# Usage: terraform init -backend-config=environments/prod/backend.hcl -reconfigure
bucket       = "caizin-terraform-state-126697143036"
key          = "prod/unibasictojava-website/terraform.tfstate"
region       = "ap-south-1"
encrypt      = true
use_lockfile = true # Native S3 state locking (requires Terraform >= 1.11)
