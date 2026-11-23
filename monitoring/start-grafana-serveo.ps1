param(
    [int] $LocalPort = 3001,
    [int] $CheckIntervalSeconds = 30,
    [int] $FailuresBeforeRestart = 3
)

$ErrorActionPreference = 'Continue'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$StateFile = Join-Path $PSScriptRoot '.grafana-tunnel-url'
$OutLog = Join-Path $PSScriptRoot 'serveo-tunnel.out.log'
$ErrLog = Join-Path $PSScriptRoot 'serveo-tunnel.err.log'
$ComposeFile = Join-Path $PSScriptRoot 'docker-compose.yml'
$RedirectFile = Join-Path $RepoRoot 'docs\index.html'
$GitExe = 'D:\Temp\PortableGit\cmd\git.exe'
$TunnelRegex = 'https://[a-z0-9-]+\.serveousercontent\.com'

function Write-Log {
    param([string] $Message)
    Write-Output ("{0} {1}" -f (Get-Date -Format o), $Message)
}

function Get-CurrentUrl {
    if (Test-Path $StateFile) {
        $url = (Get-Content $StateFile -Raw).Trim()
        if ($url -match $TunnelRegex) { return $url }
    }
    $html = Get-Content $RedirectFile -Raw
    $match = [regex]::Match($html, $TunnelRegex)
    if ($match.Success) { return $match.Value }
    return $null
}

function Test-TunnelUrl {
    param([string] $Url)
    if (-not $Url) { return $false }
    try {
        $code = & curl.exe -sS -L --max-time 20 -o NUL -w '%{http_code}' `
            -H 'serveo-skip-browser-warning: true' "$Url/api/health"
        return ($code -eq '200')
    } catch {
        return $false
    }
}

function Start-ServeoTunnel {
    Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -eq 'ssh.exe' -and
            $_.CommandLine -like '*serveo.net*' -and
            $_.CommandLine -like "*80:localhost:$LocalPort*"
        } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    Start-Sleep -Seconds 2

    $arguments = @(
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'ServerAliveInterval=30',
        '-o', 'ExitOnForwardFailure=yes',
        '-R', "80:localhost:$LocalPort",
        'serveo.net'
    )
    $proc = Start-Process -FilePath 'ssh' -ArgumentList $arguments `
        -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog `
        -WindowStyle Hidden -PassThru
    Write-Log "started Serveo tunnel PID=$($proc.Id)"

    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Seconds 5
        $output = Get-Content $OutLog -Raw -ErrorAction SilentlyContinue
        if ($output) {
            $match = [regex]::Match($output, $TunnelRegex)
            if ($match.Success) { return $match.Value }
        }
    }
    return $null
}

function Update-PublicUrl {
    param([string] $OldUrl, [string] $NewUrl)

    [IO.File]::WriteAllText($StateFile, $NewUrl, [Text.UTF8Encoding]::new($false))

    $compose = [IO.File]::ReadAllText($ComposeFile)
    $compose = [regex]::Replace(
        $compose,
        'GF_SERVER_ROOT_URL: "[^"]+"',
        ('GF_SERVER_ROOT_URL: "{0}"' -f $NewUrl)
    )
    [IO.File]::WriteAllText($ComposeFile, $compose, [Text.UTF8Encoding]::new($false))

    $html = [IO.File]::ReadAllText($RedirectFile)
    $html = $html.Replace($OldUrl, $NewUrl)
    [IO.File]::WriteAllText($RedirectFile, $html, [Text.UTF8Encoding]::new($false))

    Write-Log "updating Grafana root URL to $NewUrl"
    Push-Location $PSScriptRoot
    try {
        & docker compose up -d --force-recreate grafana 2>&1 | Out-Null
    } finally {
        Pop-Location
    }

    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Seconds 5
        try {
            $code = & curl.exe -sS --max-time 10 -o NUL -w '%{http_code}' http://localhost:$LocalPort/api/health
            if ($code -eq '200') { break }
        } catch {}
    }

    & $GitExe -C $RepoRoot add docs/index.html monitoring/docker-compose.yml 2>&1 | Out-Null
    & $GitExe -C $RepoRoot commit -m "Update Grafana tunnel URL" 2>&1 | Out-Null
    & $GitExe -C $RepoRoot push origin main 2>&1 | Out-Null
    Write-Log "published updated redirect to GitHub Pages"
}

Write-Log "Watching Grafana tunnel -> localhost:$LocalPort"

$currentUrl = Get-CurrentUrl
if (-not $currentUrl) {
    Write-Log "no current URL found, starting tunnel"
    $currentUrl = Start-ServeoTunnel
    if ($currentUrl) { Update-PublicUrl -OldUrl $currentUrl -NewUrl $currentUrl }
}

$failures = 0

while ($true) {
    Start-Sleep -Seconds $CheckIntervalSeconds

    if (Test-TunnelUrl $currentUrl) {
        if ($failures -gt 0) { Write-Log "tunnel healthy again: $currentUrl" }
        $failures = 0
        continue
    }

    $failures++
    Write-Log "health check failed ($failures/$FailuresBeforeRestart) for $currentUrl"

    if ($failures -lt $FailuresBeforeRestart) { continue }

    Write-Log "restarting Serveo tunnel"
    $newUrl = Start-ServeoTunnel
    if (-not $newUrl) {
        Write-Log "could not obtain a tunnel URL; retrying"
        $failures = 0
        continue
    }

    if ($newUrl -ne $currentUrl) {
        Update-PublicUrl -OldUrl $currentUrl -NewUrl $newUrl
        $currentUrl = $newUrl
    }
    $failures = 0
}
