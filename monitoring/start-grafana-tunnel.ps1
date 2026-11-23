param(
    [int] $Port = 3001,
    [string] $Subdomain = 'qa-grafana-dmand-nov26'
)

$ErrorActionPreference = 'Continue'
$url = "https://$Subdomain.loca.lt/api/health"
$outLog = Join-Path $PSScriptRoot 'grafana-tunnel.out.log'
$errLog = Join-Path $PSScriptRoot 'grafana-tunnel.err.log'

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

Write-Host "Watching Grafana tunnel https://$Subdomain.loca.lt -> localhost:$Port"

$failures = 0
$skipUntil = Get-Date

while ($true) {
    if ((Get-Date) -lt $skipUntil) {
        Start-Sleep -Seconds 10
        continue
    }

    if (Test-Tunnel) {
        if ($failures -gt 0) { Write-Host "$(Get-Date -Format o) tunnel healthy again" }
        $failures = 0
    } else {
        $failures++
        Write-Host "$(Get-Date -Format o) health check failed ($failures/3)"
        if ($failures -ge 3) {
            Write-Host "$(Get-Date -Format o) restarting $url"
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
            Start-Sleep -Seconds 25

            $tunnelOutput = Get-Content $outLog -Raw -ErrorAction SilentlyContinue
            Write-Host "$(Get-Date -Format o) tunnel output: $tunnelOutput"
            if ($tunnelOutput -notlike "*$Subdomain.loca.lt*") {
                Write-Host "$(Get-Date -Format o) subdomain temporarily unavailable; retrying in 90s"
                $skipUntil = (Get-Date).AddSeconds(90)
            }
            $failures = 0
        }
    }
    Start-Sleep -Seconds 15
}
