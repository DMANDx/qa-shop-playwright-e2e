param(
    [int] $LocalPort = 3001,
    [int] $CheckIntervalSeconds = 15,
    [int] $FailuresBeforeRestart = 2
)

$ErrorActionPreference = 'Continue'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$StateFile = Join-Path $PSScriptRoot '.grafana-tunnel-url'
$OutLog = Join-Path $PSScriptRoot 'tunnel.out.log'
$ErrLog = Join-Path $PSScriptRoot 'tunnel.err.log'
$ComposeFile = Join-Path $PSScriptRoot 'docker-compose.yml'
$ManifestFile = Join-Path $RepoRoot 'docs\tunnel.json'
$RootHtml = Join-Path $RepoRoot 'docs\index.html'
$GrafanaHtml = Join-Path $RepoRoot 'docs\grafana\index.html'
$ExploreHtml = Join-Path $RepoRoot 'docs\explore\index.html'
$GitExe = 'D:\Temp\PortableGit\cmd\git.exe'
$TunnelRegex = 'https://[a-z0-9-]+\.tunnl\.gg'

function Write-Log {
    param([string] $Message)
    Write-Host ("{0} {1}" -f (Get-Date -Format o), $Message)
}

function Read-LogText {
    param([string] $Path)
    if (-not (Test-Path $Path)) { return '' }
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } catch { return '' }
}

function Get-CurrentUrl {
    if (Test-Path $StateFile) {
        $url = (Get-Content $StateFile -Raw).Trim()
        if ($url -match $TunnelRegex) { return $matches[0] }
    }
    if (Test-Path $ManifestFile) {
        $json = Get-Content $ManifestFile -Raw | ConvertFrom-Json
        if ($json.url -match $TunnelRegex) { return $matches[0] }
    }
    return $null
}

function Test-TunnelUrl {
    param([string] $Url)
    if (-not $Url) { return $false }
    try {
        $code = & curl.exe -sS -L --max-time 15 -o NUL -w '%{http_code}' "$Url/api/health"
        return ($code -eq '200')
    } catch { return $false }
}

function Start-Tunnel {
    Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -eq 'ssh.exe' -and
            $_.CommandLine -like "*localhost:$LocalPort*" -and
            (
                $_.CommandLine -like '*proxy.tunnl.gg*' -or
                $_.CommandLine -like '*serveo.net*' -or
                $_.CommandLine -like '*pinggy.io*'
            )
        } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    Start-Sleep -Seconds 2

    $arguments = @(
        '-t',
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'ServerAliveInterval=30',
        '-o', 'ExitOnForwardFailure=yes',
        '-R', "80:localhost:$LocalPort",
        'proxy.tunnl.gg'
    )
    $proc = Start-Process -FilePath 'ssh' -ArgumentList $arguments `
        -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog `
        -WindowStyle Hidden -PassThru
    Write-Log "started tunnl tunnel PID=$($proc.Id)"

    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Seconds 5
        $match = [regex]::Match((Read-LogText $OutLog), $TunnelRegex)
        if ($match.Success) { return $match.Value }
    }
    return $null
}

function Update-PublicUrl {
    param([string] $NewUrl)

    [IO.File]::WriteAllText($StateFile, $NewUrl, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($ManifestFile, ('{{"url":"{0}"}}' -f $NewUrl), [Text.UTF8Encoding]::new($false))

    foreach ($htmlPath in @($RootHtml, $GrafanaHtml, $ExploreHtml)) {
        if (Test-Path $htmlPath) {
            $html = [IO.File]::ReadAllText($htmlPath)
            $html = [regex]::Replace($html, 'https://[a-z0-9-]+\.(serveousercontent\.com|tunnl\.gg)', $NewUrl)
            [IO.File]::WriteAllText($htmlPath, $html, [Text.UTF8Encoding]::new($false))
        }
    }

    $compose = [IO.File]::ReadAllText($ComposeFile)
    $compose = [regex]::Replace($compose, 'GF_SERVER_ROOT_URL: "[^"]+"', ('GF_SERVER_ROOT_URL: "{0}"' -f $NewUrl))
    [IO.File]::WriteAllText($ComposeFile, $compose, [Text.UTF8Encoding]::new($false))

    Write-Log "updating Grafana root URL to $NewUrl"
    Push-Location $PSScriptRoot
    try { & docker compose up -d --force-recreate grafana 2>&1 | Out-Null } finally { Pop-Location }

    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Seconds 5
        try {
            $code = & curl.exe -sS --max-time 8 -o NUL -w '%{http_code}' "http://localhost:$LocalPort/api/health"
            if ($code -eq '200') { break }
        } catch {}
    }

    & $GitExe -C $RepoRoot add docs/tunnel.json docs/index.html docs/grafana/index.html docs/explore/index.html monitoring/docker-compose.yml 2>&1 | Out-Null
    & $GitExe -C $RepoRoot commit -m "Update Grafana tunnel URL" 2>&1 | Out-Null
    & $GitExe -C $RepoRoot push origin main 2>&1 | Out-Null
    Write-Log "published updated redirect to GitHub Pages"
}

Write-Log "Watching Grafana tunnel -> localhost:$LocalPort"

$currentUrl = Get-CurrentUrl
if (-not (Test-TunnelUrl $currentUrl)) {
    Write-Log "current tunnel unavailable, starting a new one"
    $currentUrl = Start-Tunnel
    if ($currentUrl) { Update-PublicUrl -NewUrl $currentUrl }
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

    Write-Log "restarting tunnel"
    $newUrl = Start-Tunnel
    if (-not $newUrl) {
        Write-Log "could not obtain a tunnel URL; retrying"
        $failures = 0
        continue
    }

    if ($newUrl -ne $currentUrl) {
        Update-PublicUrl -NewUrl $newUrl
        $currentUrl = $newUrl
    }
    $failures = 0
}
