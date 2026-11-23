param(
    [string] $BaseUrl = $env:SHOP_BASE_URL
)

$ErrorActionPreference = 'Stop'

if ($BaseUrl) {
    $env:SHOP_BASE_URL = $BaseUrl
}

Write-Host "Shop under test: $($env:SHOP_BASE_URL ?? 'http://localhost:3000')"

dotnet restore
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

dotnet build --no-restore
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$playwrightScript = Join-Path $PSScriptRoot 'bin/Debug/net8.0/playwright.ps1'
if (Test-Path $playwrightScript) {
    Write-Host 'Installing Chromium for Playwright (if needed)...'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $playwrightScript install chromium
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

dotnet test --no-build --logger 'console;verbosity=normal'
exit $LASTEXITCODE
