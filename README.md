# unibasictojava-website

The [unibasictojava.com](https://unibasictojava.com) marketing site and the AWS
infrastructure that serves it.

S3 (private) → CloudFront (OAC) → ACM → Route 53, built on the
[terraform-aws-modules](https://registry.terraform.io/namespaces/terraform-aws-modules)
CloudFront, S3 and ACM modules.

## Layout

```
.
├── site/                       the site - a single self-contained index.html
├── scripts/                    deploy.ps1 / deploy.cmd - S3 sync + invalidation
├── environments/
│   └── prod/
│       ├── backend.hcl         remote state config
│       └── terraform.tfvars    per-environment inputs
├── checks.tf                   cross-variable plan-time assertions
├── locals.tf                   name_prefix, common_tags, derived values
├── main.tf                     buckets, ACM, CloudFront, bucket policy, DNS
├── outputs.tf
├── providers.tf                default + us-east-1 aliased provider
├── variables.tf
├── versions.tf                 required versions + S3 backend
└── Makefile
```

## What gets created

| Resource | Purpose |
| --- | --- |
| S3 bucket | Origin. Fully private — Block Public Access on, website hosting off. |
| Origin Access Control | Lets CloudFront sign requests to the private bucket with SigV4. |
| Bucket policy | Grants `s3:GetObject` to `cloudfront.amazonaws.com`, scoped by `AWS:SourceArn` to this one distribution. |
| CloudFront distribution | HTTPS, HTTP/2 + HTTP/3, compression, managed security headers. |
| ACM certificate | DNS-validated, created in `us-east-1` via an aliased provider. |
| Route 53 A + AAAA aliases | One pair per domain in `aliases`. |
| Logs bucket | Optional (`enable_logging = true`), 90-day expiry. |

Certificate, DNS records and logs bucket are all conditional — with
`domain_name = ""` and `enable_logging = false` (the current settings) none of
them are created.

## Prerequisites

- Terraform `~> 1.11` — required for native S3 state locking (`use_lockfile`)
- AWS CLI v2.9+ (2.9 introduced the `sso_session` format)
- Credentials with permission over S3, CloudFront, ACM, Route 53 and IAM

## Authentication

The target account is chosen by the environment rather than committed to the
repo, so no `aws_profile` variable exists:

```powershell
$env:AWS_PROFILE = "<your-sso-profile>"
aws sso login
aws sts get-caller-identity   # confirm the account before applying
```

Terraform reads the SSO token cache directly, so no static access keys are
needed anywhere. The token expires — typically after 8 to 12 hours — and the
fix is another `aws sso login`, not a config change. The same setup works
unchanged in CI, where a GitHub Actions OIDC role supplies the credentials.

## Usage

```bash
export AWS_PROFILE=<sso-profile>

make plan ENV=prod      # init + fmt + validate + plan, writes tfplan
make apply ENV=prod     # applies the saved tfplan
make destroy ENV=prod
make fmt
make scan               # checkov + trivy
```

Then publish the site:

```
scripts\deploy.cmd
```

`scripts\deploy.ps1` is the PowerShell equivalent; both do the same two-pass
upload and invalidation. Assets get a one-year immutable cache; `.html`, `.json`,
`.xml` and `.txt` get `must-revalidate` so a deploy never serves stale
references.

## Running without a custom domain

Set `domain_name = ""` (the current `terraform.tfvars`). Terraform skips the
certificate and the Route 53 records entirely, and the distribution serves on
its AWS-issued hostname over HTTPS:

```
https://d1a2b3c4e5f6g7.cloudfront.net
```

Attaching a domain later is a re-apply, not a rebuild — fill in `domain_name`
and `route53_zone_name`, run `make apply`, and the same distribution picks up
the certificate and aliases. The bucket, the distribution id and the URL all
survive, so nothing needs redeploying.

## If your DNS is not in Route 53

Leave `route53_zone_name` empty. The certificate cannot be validated
automatically, so apply in two passes:

```bash
terraform apply -target=module.acm
terraform output acm_validation_records   # add these CNAMEs at your registrar
terraform apply                           # once the cert shows Issued
```

Afterwards point your domain at the `cloudfront_domain_name` output with a
CNAME. Note that a bare apex domain (`example.com`) cannot use a CNAME — it
needs Route 53 alias records or a provider with CNAME flattening such as
Cloudflare (set to DNS-only, not proxied, to avoid stacking two CDNs).

## Adding an environment

Create `environments/<new-env>/backend.hcl` and
`environments/<new-env>/terraform.tfvars` following the `prod/` layout, then run
`make plan ENV=<new-env>`. State keys follow `<env>/<component>/terraform.tfstate`.

## Notes

- `spa_mode = true` maps 403/404 to `/index.html` with a 200 so a client-side
  router handles unknown paths. Set it to `false` for a multi-page site, where a
  missing page should genuinely return 404.
- For a static site generator that emits `/about/index.html` and needs clean
  `/about` URLs, add a CloudFront Function on the viewer-request event to append
  `index.html` to directory paths.
- `price_class` defaults to `PriceClass_100` (North America + Europe). Use
  `PriceClass_200` to include Asia, or `PriceClass_All` for every edge location.
- First `apply` takes a few minutes while the distribution deploys; the module
  is set to `wait_for_deployment = false` so Terraform returns without blocking.
