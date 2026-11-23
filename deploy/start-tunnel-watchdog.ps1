param(
    [int] $Port = 3000,
    [string] $Subdomain = 'qa-shop-dmand-2026'
)

$ErrorActionPreference = 'Continue'
$url = "https://$Subdomain.loca.lt/api/health"
$logDir = $PSScriptRoot
$outLog = Join-Path $logDir 'tunnel.out.log'
$errLog = Join-Path $logDir 'tunnel.err.log'

function Test-Tunnel {
    try {
        $response = Invoke-WebRequest -Uri $url `
            -Headers @{ 'bypass-tunnel-reminder' = '1' } `
            -TimeoutSec 20 -UseBasicParsing
        return $response.StatusCode -eq 200
    } catch {
        return $false
    }
}

Write-Host "Watching tunnel https://$Subdomain.loca.lt -> localhost:$Port"

while ($true) {
    if (-not (Test-Tunnel)) {
        Write-Host "$(Get-Date -Format o) tunnel unhealthy, restarting $url"

        # Previous localtunnel chains (npx -> cmd -> lt.js) may still be running
        # but pointing at a stale/dead upstream connection.
        Get-CimInstance Win32_Process |
            Where-Object {
                $_.Name -in @('node.exe', 'cmd.exe') -and
                $_.CommandLine -like "*--subdomain $Subdomain*"
            } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

        Start-Sleep -Seconds 2
        $proc = Start-Process -FilePath 'cmd.exe' `
            -ArgumentList @('/c', 'npx', '--yes', 'localtunnel', '--port', "$Port", '--subdomain', $Subdomain) `
            -RedirectStandardOutput $outLog -RedirectStandardError $errLog `
            -WindowStyle Hidden -PassThru
        Write-Host "$(Get-Date -Format o) started localtunnel PID=$($proc.Id)"
        Start-Sleep -Seconds 20

        $tunnelOutput = Get-Content $outLog -Raw -ErrorAction SilentlyContinue
        Write-Host "$(Get-Date -Format o) tunnel output: $tunnelOutput"
        if ($tunnelOutput -notlike "*$Subdomain.loca.lt*") {
            Write-Host "$(Get-Date -Format o) subdomain unavailable; killing chain and retrying"
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Seconds 10
}
