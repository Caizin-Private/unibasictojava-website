# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Terraform workflow

Always pass both `-backend-config` and `-var-file` — there is no default environment. `ENV` defaults to `dev` in the Makefile, but `dev` does not exist in this repo; `prod` is the only environment, so always pass `ENV=prod` explicitly.

`AWS_PROFILE` must be set in the shell before running any `make` or `terraform` command — it is not managed by the Makefile.

```bash
export AWS_PROFILE=<sso-profile>
aws sso login
aws sts get-caller-identity    # confirm the account before applying

make plan ENV=prod       # runs init + fmt + validate + plan, writes tfplan
make apply ENV=prod      # applies the saved tfplan file
make validate ENV=prod
make fmt                 # formats all .tf files recursively
make destroy ENV=prod

make scan                # checkov + trivy against HIGH/CRITICAL severity

# Manual workflow (equivalent to make plan/apply)
terraform init -backend-config=environments/prod/backend.hcl -reconfigure
terraform plan -var-file=environments/prod/terraform.tfvars -out=tfplan
terraform apply tfplan
```

Requires Terraform `~> 1.11` (for native S3 state locking via `use_lockfile = true`).

## Repository layout

This repo holds both the site and the infrastructure that serves it.

| Path | Purpose |
| --- | --- |
| `site/` | The site itself — a single self-contained `index.html`. No build step. |
| `environments/<env>/` | `backend.hcl` (remote state) and `terraform.tfvars` (per-env inputs). |
| `*.tf` | Root module. There are no local modules; everything is `terraform-aws-modules`. |

## Architecture

S3 (private) → CloudFront (OAC) → ACM → Route 53.

The bucket is fully private: Block Public Access on, static website hosting off, `BucketOwnerEnforced`. CloudFront reaches it over the REST endpoint using an Origin Access Control that signs with SigV4, and the bucket policy grants `s3:GetObject` to `cloudfront.amazonaws.com` scoped by `AWS:SourceArn` to this one distribution. There is no public path to the bucket.

Cache behaviour is deliberately split in two:

| Path | Policy | Why |
| --- | --- | --- |
| `/index.html` | `Managed-CachingDisabled` | The entrypoint must revalidate, or a deploy keeps serving stale asset references. |
| everything else | `Managed-CachingOptimized` | Fingerprinted assets are immutable and cache for a year. |

Publishing must mirror this split: two `aws s3 sync` passes setting different `Cache-Control` headers, then an invalidation. The commands are in `README.md` under "Publishing the site". There is no deploy script — uploading in a single pass is the one mistake that reliably breaks a release, because a cached `index.html` keeps referencing asset filenames that no longer exist.

## Custom domain

`domain_name` is currently empty, so the site serves on its `*.cloudfront.net` hostname and Terraform skips the certificate and DNS records entirely. Attaching a domain later is a re-apply, not a rebuild — the bucket, distribution id and URL all survive.

The ACM certificate is created through the `aws.us_east_1` aliased provider in `providers.tf`, because CloudFront only reads certificates from `us-east-1` regardless of where the bucket lives.

If `route53_zone_name` is empty, the certificate cannot be validated automatically. Apply in two passes: `terraform apply -target=module.acm`, add the CNAMEs from the `acm_validation_records` output at the registrar, then apply again.

## Conventions

- **Tagging** — `Environment`, `Project`, `Owner`, `CostCenter`, `ManagedBy`, `Repo` are applied to every resource via `provider "aws" { default_tags {} }` reading `local.common_tags`.
- **Naming** — `local.name_prefix` is `${var.project}-${var.environment}`. Bucket names append the account id, because S3 bucket names are globally unique.
- **`checks.tf`** — cross-variable rules that `validation` blocks cannot express, since those cannot reference other variables. Failures surface at plan time.
- **State key pattern** — `<env>/<component>/terraform.tfstate` in the shared `caizin-terraform-state-126697143036` bucket (ap-south-1).

## Gotchas

- `viewer_certificate` is a conditional where **both branches carry the same attribute set**, including explicit `null`s. Terraform fails type unification if the two sides are objects with different attributes.
- The logs bucket uses `BucketOwnerPreferred`, not `BucketOwnerEnforced` like the site bucket — CloudFront standard logging delivers via ACL and cannot write to an ACL-disabled bucket.
- `spa_mode = true` maps 403/404 to `/index.html` with a 200. For this single-page marketing site that means a mistyped URL returns a soft 404 that search engines will index. Set it to `false` unless the site grows a client-side router.
