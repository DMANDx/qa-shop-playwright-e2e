param(
    [string] $AppDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..\qa-shop')).Path,
    [int] $Port = 3000
)

$ErrorActionPreference = 'Continue'
$env:PORT = "$Port"
$env:ALLOW_TEST_RESET = '1'

Write-Host "Watching qa-shop in $AppDir on port $Port"

while ($true) {
    $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if (-not $listener) {
        Write-Host "$(Get-Date -Format o) starting node server.js"
        Start-Process -FilePath node -ArgumentList 'server.js' -WorkingDirectory $AppDir `
            -RedirectStandardOutput (Join-Path $PSScriptRoot 'shop.log') `
            -RedirectStandardError (Join-Path $PSScriptRoot 'shop.err.log') `
            -WindowStyle Hidden
    }
    Start-Sleep -Seconds 10
}
