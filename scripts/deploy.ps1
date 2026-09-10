<#
.SYNOPSIS
  Publish the built site to S3 and invalidate the CloudFront cache.

.EXAMPLE
  .\scripts\deploy.ps1 -Profile unicode-to-java
#>
[CmdletBinding()]
param(
    [string]$DistPath = "./dist",
    [string]$TerraformDir = "./terraform",
    [string]$Profile = $env:AWS_PROFILE
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $DistPath)) {
    throw "Build output not found at $DistPath. Run your build first."
}

# Every aws call takes the same profile flag, or none when running under a role.
$awsArgs = @()
if ($Profile) {
    $awsArgs = @("--profile", $Profile)
    $env:AWS_PROFILE = $Profile
}

# SSO tokens expire, and an expired one otherwise surfaces as a confusing
# AccessDenied partway through the sync.
try {
    aws sts get-caller-identity @awsArgs --output text | Out-Null
}
catch {
    throw "AWS credentials are not valid. Run: aws sso login --profile $Profile"
}

$bucket = (terraform -chdir=$TerraformDir output -raw site_bucket_name)
$distId = (terraform -chdir=$TerraformDir output -raw cloudfront_distribution_id)

Write-Host "Bucket:       $bucket"
Write-Host "Distribution: $distId"

# Fingerprinted assets are immutable, so they get a one-year cache. Everything
# matched here is excluded from the second pass below.
aws s3 sync $DistPath "s3://$bucket" @awsArgs `
    --delete `
    --cache-control "public,max-age=31536000,immutable" `
    --exclude "*.html" `
    --exclude "*.json" `
    --exclude "*.xml" `
    --exclude "*.txt"

# Entrypoints and metadata must revalidate on every request, otherwise a deploy
# keeps serving stale references to the old asset filenames.
aws s3 sync $DistPath "s3://$bucket" @awsArgs `
    --delete `
    --cache-control "public,max-age=0,must-revalidate" `
    --exclude "*" `
    --include "*.html" `
    --include "*.json" `
    --include "*.xml" `
    --include "*.txt"

$invalidation = aws cloudfront create-invalidation @awsArgs `
    --distribution-id $distId `
    --paths "/*" `
    --query "Invalidation.Id" `
    --output text

Write-Host "Invalidation created: $invalidation"

$url = (terraform -chdir=$TerraformDir output -raw site_url)
Write-Host "Deployed: $url"
