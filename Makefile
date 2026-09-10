ENV        ?= prod
BACKEND     = environments/$(ENV)/backend.hcl
TFVARS      = environments/$(ENV)/terraform.tfvars
PLAN_FILE   = tfplan
SITE_DIR   ?= site

.PHONY: init fmt validate plan apply destroy scan deploy

init:
	terraform init -backend-config=$(BACKEND) -reconfigure

fmt:
	terraform fmt -recursive

validate: init fmt
	terraform validate

plan: init fmt validate
	terraform plan -var-file=$(TFVARS) -out=$(PLAN_FILE)

apply: init
	terraform apply $(PLAN_FILE)

destroy: init
	terraform destroy -var-file=$(TFVARS)

scan:
	checkov -d . --framework terraform --quiet
	trivy config . --severity HIGH,CRITICAL

# Publishes $(SITE_DIR) to S3 and invalidates CloudFront. Reads the bucket and
# distribution id from terraform outputs, so `apply` must have run first.
deploy:
	powershell -ExecutionPolicy Bypass -File scripts/deploy.ps1 -SitePath $(SITE_DIR)
