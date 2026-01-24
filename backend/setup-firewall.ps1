# Windows Firewall Rule for Node.js Backend
# Run this script as Administrator

Write-Host "Creating Windows Firewall rule for Node.js on port 5000..." -ForegroundColor Cyan

# Remove existing rule if it exists
Remove-NetFirewallRule -DisplayName "Node.js Backend Server" -ErrorAction SilentlyContinue

# Create new inbound rule
New-NetFirewallRule -DisplayName "Node.js Backend Server" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 5000 `
    -Action Allow `
    -Profile Any `
    -Enabled True

Write-Host "✅ Firewall rule created successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Port 5000 is now accessible from your network." -ForegroundColor Green
Write-Host "You can now connect from your Android device at: http://192.168.0.116:5000" -ForegroundColor Yellow
Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
