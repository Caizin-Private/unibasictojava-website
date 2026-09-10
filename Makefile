ENV        ?= dev
BACKEND     = environments/$(ENV)/backend.hcl
TFVARS      = environments/$(ENV)/terraform.tfvars
PLAN_FILE   = tfplan

.PHONY: init fmt validate plan apply destroy scan

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
