<#
.SYNOPSIS
    Поднимает весь стенд: магазин, публичный туннель магазина,
    Prometheus + Grafana и публичный туннель Grafana.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\start-all.ps1

.NOTES
    Идемпотентно: если watchdog уже запущен, он не дублируется.
    Остановка: .\stop-all.ps1
#>
[CmdletBinding()]
param(
    [switch] $SkipMonitoring
)

$ErrorActionPreference = 'Continue'

$RepoRoot      = $PSScriptRoot
$DeployDir     = Join-Path $RepoRoot 'deploy'
$MonitoringDir = Join-Path $RepoRoot 'monitoring'
$ShopDir       = Join-Path (Split-Path -Parent $RepoRoot) 'qa-shop'

$ShopHealthUrl = 'https://qa-shop-dmand-2026.loca.lt/api/health'
$PagesBase     = 'https://dmandx.github.io/qa-shop-playwright-e2e'
$StateFile     = Join-Path $MonitoringDir '.grafana-tunnel-url'

$LogDir = Join-Path $env:TEMP 'qa-shop-watchdogs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

function Test-WatchdogRunning {
    param([string] $ScriptName)
    $self = $PID
    return [bool] (Get-CimInstance Win32_Process | Where-Object {
        $_.ProcessId -ne $self -and
        $_.Name -eq 'powershell.exe' -and
        $_.CommandLine -like "*$ScriptName*"
    })
}

function Start-Watchdog {
    param(
        [string] $ScriptPath,
        [string] $LogName
    )
    $name = Split-Path -Leaf $ScriptPath
    if (Test-WatchdogRunning $name) {
        Write-Host "  ! $name уже запущен, пропускаем"
        return
    }
    if (-not (Test-Path $ScriptPath)) {
        Write-Warning "  ! Не найден $ScriptPath - пропускаем"
        return
    }
    $quoted = '"{0}"' -f $ScriptPath
    $proc = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $quoted) `
        -RedirectStandardOutput (Join-Path $LogDir ($LogName + '.log')) `
        -RedirectStandardError  (Join-Path $LogDir ($LogName + '.err.log')) `
        -WindowStyle Hidden -PassThru
    Write-Host "  + $name запущен (PID $($proc.Id))"
}

function Wait-Port {
    param(
        [int] $Port,
        [string] $Label,
        [int] $TimeoutSeconds = 45
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
            Write-Host "  OK $Label (порт $Port слушается)"
            return $true
        }
        Start-Sleep -Seconds 2
    }
    Write-Warning "  ! $Label не поднялся за ${TimeoutSeconds}c"
    return $false
}

function Invoke-CurlCode {
    param(
        [string] $Url,
        [hashtable] $Headers = @{},
        [int] $TimeoutSeconds = 12
    )
    $argsList = @('-sS', '-L', '--max-time', "$TimeoutSeconds", '-o', 'NUL', '-w', '%{http_code}')
    foreach ($key in $Headers.Keys) {
        $argsList += @('-H', ('{0}: {1}' -f $key, $Headers[$key]))
    }
    $argsList += $Url
    try { return (& curl.exe @argsList).Trim() } catch { return '' }
}

function Wait-Http {
    param(
        [string] $Url,
        [string] $Label,
        [hashtable] $Headers = @{},
        [int] $TimeoutSeconds = 120
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ((Invoke-CurlCode -Url $Url -Headers $Headers) -eq '200') {
            Write-Host "  OK $Label"
            return $true
        }
        Start-Sleep -Seconds 5
    }
    Write-Warning "  ! $Label не ответил 200 за ${TimeoutSeconds}c"
    return $false
}

function Wait-GrafanaPublic {
    param([int] $TimeoutSeconds = 240)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $local = if (Test-Path $StateFile) { (Get-Content $StateFile -Raw).Trim() } else { '' }
        if ($local) {
            $code = Invoke-CurlCode -Url "$local/api/health"
            try {
                $remoteJson = & curl.exe -sS --max-time 12 "$PagesBase/tunnel.json?ts=$([DateTime]::UtcNow.Ticks)"
                $remote = ($remoteJson | ConvertFrom-Json).url
            } catch { $remote = '' }
            if ($code -eq '200' -and $remote -eq $local) {
                Write-Host "  OK tunneling Grafana: $local (Pages в синке)"
                return $true
            }
        }
        Start-Sleep -Seconds 10
    }
    Write-Warning '  ! Публичная Grafana не синхронизировалась за 240c - проверьте логи watchdog-а'
    return $false
}

Write-Host '========================================================'
Write-Host ' Подъём стенда QA Shop'
Write-Host " Каталог: $RepoRoot"
Write-Host " Логи:    $LogDir"
Write-Host '========================================================'

if (-not (Test-Path $ShopDir)) {
    Write-Error "Не найден каталог магазина: $ShopDir"
    exit 1
}

Write-Host ''
Write-Host '[1/4] Магазин (node server.js, порт 3000)'
Start-Watchdog -ScriptPath (Join-Path $DeployDir 'start-shop-watchdog.ps1') -LogName 'shop-watchdog'
Wait-Port -Port 3000 -Label 'Магазин' | Out-Null

Write-Host ''
Write-Host '[2/4] Публичный туннель магазина (localtunnel)'
Start-Watchdog -ScriptPath (Join-Path $DeployDir 'start-tunnel-watchdog.ps1') -LogName 'shop-tunnel-watchdog'
Wait-Http -Url $ShopHealthUrl -Label 'Публичный магазин' `
    -Headers @{ 'bypass-tunnel-reminder' = '1' } -TimeoutSeconds 120 | Out-Null

$dockerOk = $false
if ($SkipMonitoring) {
    Write-Host ''
    Write-Host '[3/4] Prometheus + Grafana - пропущено (-SkipMonitoring)'
} else {
    Write-Host ''
    Write-Host '[3/4] Prometheus + Grafana (Docker Compose)'
    Push-Location $MonitoringDir
    try { & docker compose up -d; $dockerOk = ($LASTEXITCODE -eq 0) }
    catch { $dockerOk = $false }
    finally { Pop-Location }
    if ($dockerOk) {
        Wait-Port -Port 9090 -Label 'Prometheus' | Out-Null
        Wait-Port -Port 3001 -Label 'Grafana' | Out-Null
    } else {
        Write-Warning '  ! Docker недоступен - Grafana и её туннель не поднимаем'
    }
}

if ($dockerOk) {
    Write-Host ''
    Write-Host '[4/4] Публичный туннель Grafana (tunnl.gg + GitHub Pages)'
    Start-Watchdog -ScriptPath (Join-Path $MonitoringDir 'start-grafana-tunnel.ps1') -LogName 'grafana-tunnel-watchdog'
    Wait-GrafanaPublic | Out-Null
}

Write-Host ''
Write-Host '========================================================'
Write-Host ' Итог'
Write-Host " Магазин:  https://qa-shop-dmand-2026.loca.lt"
Write-Host " Grafana:  $PagesBase/grafana/"
Write-Host " Explore:  $PagesBase/explore/"
Write-Host " Репозиторий: https://github.com/DMANDx/qa-shop-playwright-e2e"
Write-Host " Остановка: powershell -NoProfile -ExecutionPolicy Bypass -File .\stop-all.ps1"
Write-Host '========================================================'
