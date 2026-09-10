@echo off
REM Publish the built site to S3 and invalidate the CloudFront cache.
REM Usage:  scripts\deploy.cmd [dist-folder]     (run from the project root)

setlocal

set "DIST=%~1"
if "%DIST%"=="" set "DIST=dist"

if not exist "%DIST%" (
  echo ERROR: build output not found at "%DIST%".
  exit /b 1
)

REM SSO tokens expire. Catching that here avoids a confusing AccessDenied
REM partway through the upload, after some files have already landed.
aws sts get-caller-identity >nul 2>&1
if errorlevel 1 (
  echo ERROR: AWS credentials are not valid.
  echo Run: aws sso login
  exit /b 1
)

for /f "delims=" %%i in ('terraform -chdir=terraform output -raw site_bucket_name') do set "BUCKET=%%i"
for /f "delims=" %%i in ('terraform -chdir=terraform output -raw cloudfront_distribution_id') do set "DISTID=%%i"

if "%BUCKET%"=="" (
  echo ERROR: could not read terraform outputs. Has "terraform apply" run?
  exit /b 1
)

echo Bucket:       %BUCKET%
echo Distribution: %DISTID%
echo.

REM Fingerprinted assets are immutable, so they get a one-year cache.
echo [1/3] Uploading assets...
aws s3 sync "%DIST%" "s3://%BUCKET%" --delete ^
  --cache-control "public,max-age=31536000,immutable" ^
  --exclude "*.html" --exclude "*.json" --exclude "*.xml" --exclude "*.txt"
if errorlevel 1 exit /b 1

REM Entrypoints must revalidate every time, otherwise a deploy keeps serving
REM stale references to the previous asset filenames.
echo [2/3] Uploading entrypoints...
aws s3 sync "%DIST%" "s3://%BUCKET%" --delete ^
  --cache-control "public,max-age=0,must-revalidate" ^
  --exclude "*" ^
  --include "*.html" --include "*.json" --include "*.xml" --include "*.txt"
if errorlevel 1 exit /b 1

echo [3/3] Invalidating CloudFront cache...
for /f "delims=" %%i in ('aws cloudfront create-invalidation --distribution-id %DISTID% --paths "/*" --query "Invalidation.Id" --output text') do set "INVAL=%%i"
echo Invalidation: %INVAL%

for /f "delims=" %%i in ('terraform -chdir=terraform output -raw site_url') do set "URL=%%i"
echo.
echo Deployed: %URL%

endlocal
