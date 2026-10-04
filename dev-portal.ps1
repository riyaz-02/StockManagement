<#
  dev-portal.ps1 - starts the web portal for development (local dev database ONLY).
  Needs the local API running (.\dev-local.ps1 starts DB + API + app; or: cd backend; node scripts/local-db.js; node server.js).
  Opens http://localhost:8080
#>
param([int]$Port = 8080)
$ErrorActionPreference = 'Stop'
$portal = Join-Path $PSScriptRoot 'portal'
if (-not (Test-Path (Join-Path $portal 'vendor'))) { Push-Location $portal; composer install --no-interaction; Pop-Location }
if (-not (Test-Path (Join-Path $portal '.env'))) { Copy-Item (Join-Path $portal '.env.example') (Join-Path $portal '.env') }
try { $ok = (Invoke-WebRequest 'http://localhost:5000/health' -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200 } catch { $ok = $false }
if (-not $ok) { Write-Host 'The local API is not running on :5000. Start it first (.\dev-local.ps1 or cd backend; node server.js).' -ForegroundColor Yellow }
Write-Host "Portal: http://localhost:$Port  (dev)" -ForegroundColor Green
Set-Location $portal
# the PHP limits are raised so an app (an APK, 40 MB or more) can be uploaded on Admin > App updates
php -d upload_max_filesize=300M -d post_max_size=310M -d memory_limit=512M -d max_execution_time=0 -S "localhost:$Port" -t public router.php
