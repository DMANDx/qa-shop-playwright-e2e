<#
.SYNOPSIS
    Останавливает весь стенд. Watchdog-и убиваются первыми,
    иначе они поднимут магазин и туннели обратно.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\stop-all.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$RepoRoot      = $PSScriptRoot
$MonitoringDir = Join-Path $RepoRoot 'monitoring'
$self          = $PID

function Stop-Matching {
    param(
        [string] $Label,
        [scriptblock] $Predicate
    )
    $found = @(Get-CimInstance Win32_Process | Where-Object {
        $_.ProcessId -ne $self -and (& $Predicate $_)
    })
    foreach ($proc in $found) {
        Write-Host "  - ${Label}: PID $($proc.ProcessId)"
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }
    if ($found.Count -eq 0) { Write-Host "  · ${Label}: не найдено" }
}

Write-Host '========================================================'
Write-Host ' Остановка стенда QA Shop'
Write-Host '========================================================'

Write-Host ''
Write-Host '[1/4] Watchdog-и (сначала они!)'
$watchdogNames = @(
    'start-shop-watchdog.ps1',
    'start-tunnel-watchdog.ps1',
    'start-grafana-tunnel.ps1',
    'qa-shop-app-watchdog.ps1',
    'qa-shop-tunnel-watchdog-v2.ps1',
    'start-grafana-serveo.ps1'
)
Stop-Matching -Label 'watchdog' -Predicate {
    param($p)
    $line = $p.CommandLine
    $p.Name -eq 'powershell.exe' -and
        @($watchdogNames | Where-Object { $line -like "*$_*" }).Count -gt 0
}

Start-Sleep -Seconds 2

Write-Host ''
Write-Host '[2/4] Туннели (SSH / localtunnel)'
Stop-Matching -Label 'ssh-туннель' -Predicate {
    param($p)
    $line = $p.CommandLine
    $p.Name -eq 'ssh.exe' -and
        ($line -like '*localhost:3000*' -or $line -like '*localhost:3001*') -and
        ($line -like '*tunnl.gg*' -or $line -like '*serveo.net*' -or
         $line -like '*pinggy.io*' -or $line -like '*localhost.run*')
}
Stop-Matching -Label 'localtunnel' -Predicate {
    param($p)
    $line = $p.CommandLine
    $p.Name -in @('node.exe', 'cmd.exe') -and
        ($line -like '*localtunnel*' -or $line -like '*lt.js*' -or
         $line -like '*qa-shop-dmand-2026*')
}

Write-Host ''
Write-Host '[3/4] Магазин (node server.js)'
Stop-Matching -Label 'node server.js' -Predicate {
    param($p)
    $p.Name -eq 'node.exe' -and $p.CommandLine -like '*server.js*'
}

Write-Host ''
Write-Host '[4/4] Docker: Prometheus + Grafana'
Push-Location $MonitoringDir
try { & docker compose stop }
catch { Write-Warning "  ! Не удалось остановить Docker: $_" }
finally { Pop-Location }

Write-Host ''
Write-Host '--- Проверка ---'
$busy = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -in @(3000, 3001, 8443, 9090) }
if ($busy) {
    $busy | Select-Object LocalPort, OwningProcess | Format-Table
} else {
    Write-Host '  Порты 3000, 3001, 8443, 9090 свободны'
}
Get-CimInstance Win32_Process | Where-Object {
    $_.ProcessId -ne $self -and
    ($_.Name -in @('ssh.exe', 'ngrok.exe', 'cloudflared.exe', 'bore.exe') -or
     ($_.Name -eq 'node.exe' -and $_.CommandLine -match 'localtunnel|lt\.js'))
} | Select-Object ProcessId, Name | Format-Table

Write-Host 'Готово. Поднять обратно: .\start-all.ps1'
