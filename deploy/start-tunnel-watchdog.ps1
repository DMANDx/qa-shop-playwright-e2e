param(
    [int] $Port = 3000,
    [string] $Subdomain = 'qa-shop-dmand'
)

$ErrorActionPreference = 'Continue'

Write-Host "Watching tunnel https://$Subdomain.loca.lt -> localhost:$Port"

while ($true) {
    $running = Get-CimInstance Win32_Process |
        Where-Object {
            $_.CommandLine -like "*localtunnel*--subdomain $Subdomain*" -or
            $_.CommandLine -like "*lt.js*--subdomain $Subdomain*"
        }

    if (-not $running) {
        Write-Host "$(Get-Date -Format o) starting localtunnel"
        & npx --yes localtunnel --port $Port --subdomain $Subdomain 2>&1
        Write-Host "$(Get-Date -Format o) tunnel exited, restarting in 5s"
    }

    Start-Sleep -Seconds 5
}
