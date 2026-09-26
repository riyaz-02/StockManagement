<#
  dev-local.ps1 — one command for local development.

  Starts the local backend (if not already up), tunnels the phone's
  localhost:5000 to this PC over USB (adb reverse), then runs the Flutter app
  in local mode. Production is untouched: the app defaults to prod unless
  API_ENV=local is passed, which this script does.

  Usage:   .\dev-local.ps1            # first connected device
           .\dev-local.ps1 -Device <id>

  Local login (dev DB):  mobile 7029621489 / password Admin@123
  SAFE: backend/.env has the production DB URIs commented out and uses a
  local test database with fake data; local app builds never call production
  (including the EC2 wake Lambda). To go back to real DBs, swap the comments
  in backend/.env (a copy is in backend/.env.prod-backup).
#>
param([string]$Device = '')

$root = $PSScriptRoot
$port = 5000

# 0. Local test database (fake data, port 27018). Never touches production.
$dbUp = [bool](Get-NetTCPConnection -LocalPort 27018 -State Listen -ErrorAction SilentlyContinue)
if (-not $dbUp) {
    Write-Host 'Starting local test database...' -ForegroundColor Cyan
    Start-Process -FilePath node -ArgumentList 'scripts/local-db.js' -WorkingDirectory "$root\backend" -WindowStyle Minimized
    for ($i = 0; $i -lt 60 -and -not $dbUp; $i++) {
        Start-Sleep -Seconds 2
        $dbUp = [bool](Get-NetTCPConnection -LocalPort 27018 -State Listen -ErrorAction SilentlyContinue)
    }
    if (-not $dbUp) { Write-Host 'Local database did not start.' -ForegroundColor Red; exit 1 }
    Start-Sleep -Seconds 3   # let it finish seeding
    Push-Location "$root\backend"; node seedAdmin.js | Out-Null; Pop-Location
}
Write-Host 'Local test DB up on :27018' -ForegroundColor Green

# 1. Backend
$up = $false
try { $up = (Invoke-WebRequest "http://localhost:$port/health" -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200 } catch {}
if (-not $up) {
    Write-Host 'Starting local backend...' -ForegroundColor Cyan
    Start-Process -FilePath node -ArgumentList 'server.js' -WorkingDirectory "$root\backend" -WindowStyle Minimized
    for ($i = 0; $i -lt 40 -and -not $up; $i++) {
        Start-Sleep -Seconds 2
        try { $up = (Invoke-WebRequest "http://localhost:$port/health" -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200 } catch {}
    }
    if (-not $up) { Write-Host 'Backend did not start. Run "node server.js" in backend/ to see why.' -ForegroundColor Red; exit 1 }
}
Write-Host "Backend up on :$port" -ForegroundColor Green

# 2. USB tunnel
$adbArgs = @(); if ($Device) { $adbArgs = @('-s', $Device) }
& adb @adbArgs reverse "tcp:$port" "tcp:$port" | Out-Null

# 3. App (local mode)
Set-Location "$root\flutter_app"
$flutterArgs = @('run', '--dart-define=API_ENV=local'); if ($Device) { $flutterArgs += @('-d', $Device) }
flutter @flutterArgs
