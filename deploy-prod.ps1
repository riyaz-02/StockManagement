<#
  deploy-prod.ps1 - your manual deploy, automated:
     1. push to GitHub   2. SSH into EC2   3. git pull   4. restart   5. health check

  Usage:  .\deploy-prod.ps1            (asks before pushing and before connecting)
          .\deploy-prod.ps1 -Yes       (skip the confirmations)

  Nothing here edits data. It only pushes code and restarts the API process.
  >>> Check the CONFIG block below once - some values are best guesses. <<<
#>
param([switch]$Yes)

# -- CONFIG ------------------------------------------------------------------
$KeyFile      = "$env:USERPROFILE\OneDrive\Desktop\lgp-stock-key.pem"   # or stock-key-2.pem - whichever your EC2 uses
$SshUser      = 'ubuntu'
$Host_        = 'api.laltuguineapalace.com'                             # DNS follows the EC2 public IP after wake
$RemoteRepo   = '/home/ubuntu/StockManagement'                         # folder on EC2 that holds the git clone (confirmed from pm2 on 4 Oct 2026)
$BackendSub   = 'backend'                                              # the API (and its .env) lives in backend/ inside the clone
$Pm2Name      = 'laltu-api'
$Branch       = 'main'
$WakeUrl      = 'https://45skg376c6xml6yifrzyct75rm0isktv.lambda-url.ap-south-1.on.aws/'
# ----------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Confirm-Step($msg) {
    if ($Yes) { return }
    if ((Read-Host "$msg [y/N]") -notmatch '^(y|yes)$') { Write-Host 'Cancelled.'; exit 0 }
}
function Health {
    try { return (Invoke-WebRequest "https://$Host_/health" -UseBasicParsing -TimeoutSec 8).StatusCode -eq 200 } catch { return $false }
}

if (-not (Test-Path $KeyFile)) { Write-Host "Key file not found: $KeyFile  (edit CONFIG)" -ForegroundColor Red; exit 1 }

# 1. GitHub -------------------------------------------------------------------
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne $Branch) { Write-Host "You are on '$branch', deploy expects '$Branch'." -ForegroundColor Red; exit 1 }

$dirty = git status --porcelain -- . ':!flutter_app/android/app/.cxx'
if ($dirty) {
    Write-Host "Uncommitted changes (NOT deployed until committed):" -ForegroundColor Yellow
    $dirty | Select-Object -First 15 | ForEach-Object { "   $_" }
    Write-Host 'Commit what you want to ship first, then re-run.' -ForegroundColor Yellow
}
$ahead = git rev-list --count "origin/$Branch..HEAD"
Write-Host "Commits to push: $ahead"
git log --oneline "origin/$Branch..HEAD" | Select-Object -First 10
if ([int]$ahead -gt 0) {
    Confirm-Step "Push $ahead commit(s) to GitHub ($Branch)?"
    git push origin $Branch
} else { Write-Host 'Nothing new to push.' }
$sha = (git rev-parse --short HEAD).Trim()

# 2. Make sure the (auto-stopped) EC2 is awake --------------------------------
if (-not (Health)) {
    Write-Host 'Server not responding - waking EC2 (up to ~3 min)...' -ForegroundColor Cyan
    try { Invoke-WebRequest $WakeUrl -UseBasicParsing -TimeoutSec 20 | Out-Null } catch {}
    for ($i = 0; $i -lt 36 -and -not (Health); $i++) { Start-Sleep -Seconds 5 }
    if (-not (Health)) { Write-Host 'EC2 did not come up. Aborting.' -ForegroundColor Red; exit 1 }
}
Write-Host 'Server is up.' -ForegroundColor Green

# 3. Pull + restart over SSH ----------------------------------------------------
Confirm-Step "Connect to $SshUser@$Host_ and pull commit $sha, then restart '$Pm2Name'?"

$dir = if ($BackendSub) { "$RemoteRepo/$BackendSub" } else { $RemoteRepo }
$remote = @"
set -e
cd $RemoteRepo
BEFORE=`$(git rev-parse HEAD)
git fetch origin $Branch
git merge --ff-only origin/$Branch
AFTER=`$(git rev-parse HEAD)
echo "server: `${BEFORE:0:7} -> `${AFTER:0:7}"
cd $dir
if [ "`$BEFORE" != "`$AFTER" ] && git diff --name-only `$BEFORE `$AFTER | grep -q 'package.json\|package-lock.json'; then
  echo 'dependencies changed -> npm install'; npm install --omit=dev
fi
# config sanity: key NAMES only, never values
for k in MONGODB_URI JWT_SECRET; do
  grep -q "^`$k=" .env || echo "WARNING: `$k missing in server .env"
done
pm2 restart $Pm2Name --update-env
"@ -replace "`r", ''

ssh -i $KeyFile -o StrictHostKeyChecking=accept-new "$SshUser@$Host_" $remote
if ($LASTEXITCODE -ne 0) { Write-Host 'Remote step failed - server code may be unchanged. See output above.' -ForegroundColor Red; exit 1 }

# 4. Health check ------------------------------------------------------------------
Write-Host 'Waiting for the API to come back...'
$ok = $false
for ($i = 0; $i -lt 12 -and -not $ok; $i++) { Start-Sleep -Seconds 5; $ok = Health }
if ($ok) { Write-Host "Deployed $sha - API healthy. Verify at https://$Host_/admin/" -ForegroundColor Green }
else     { Write-Host "Restarted but /health is not answering. Check: pm2 logs $Pm2Name" -ForegroundColor Red; exit 1 }
