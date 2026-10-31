# Start a Cloudflare Quick Tunnel in front of dsh-pocket and print/QR the URL.
#
# Why this exists: dsh-pocket owns its own cloudflared child and keeps the
# assigned *.trycloudflare.com hostname in memory only, so the address is not
# readable from disk or from any HTTP endpoint. This script runs an independent
# cloudflared whose stdout we own, which makes the URL capturable, and it can
# re-emit a QR every time the tunnel restarts.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File pocket-tunnel.ps1
#   ... -Port 3081 -QrPath .\pocket-qr.png -LanToken 83959852
#
# Exit codes: 0 URL obtained, 1 cloudflared missing, 2 no URL within timeout.

param(
    [int]$Port = 3081,
    [string]$Cloudflared = '',
    [string]$QrPath = '',
    # The PUBLIC password from ~/.dsh/dsh-pocket/token. Do not pass token-lan
    # here: a *.trycloudflare.com host classifies as public, so the proxy checks
    # the public token and rejects the LAN one with "瀵嗙爜閿欒".
    [string]$PocketToken = '',
    [string]$StateFile = '',
    [int]$TimeoutSeconds = 60,
    [switch]$KeepRunning
)

$ErrorActionPreference = 'Continue'

# --- locate cloudflared -------------------------------------------------------
function Find-Cloudflared {
    if ($Cloudflared -and (Test-Path -LiteralPath $Cloudflared)) { return $Cloudflared }
    $candidates = @(
        (Join-Path $env:USERPROFILE '.dsh\dsh-pocket\bin\cloudflared.exe'),
        (Join-Path $env:USERPROFILE '.dsh\cloudflared-bin\2026.9.3-win32-x64.exe')
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
    $cmd = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$exe = Find-Cloudflared
if (-not $exe) {
    Write-Host 'ERROR: cloudflared not found. Install it or let dsh-pocket download it once.' -ForegroundColor Red
    exit 1
}

# --- make sure the pocket proxy is up ----------------------------------------
$probe = $null
try { $probe = Invoke-WebRequest "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec 5 } catch {
    if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 401) { $probe = 'auth' }
}
if (-not $probe) {
    Write-Host "WARN: nothing answering on 127.0.0.1:$Port 閳?start DSH first" -ForegroundColor Yellow
}

# --- spawn cloudflared with capturable output --------------------------------
# The machine-wide socks proxy would send the tunnel's edge connection through
# 127.0.0.1:10808 and break it (error 1033), so the child gets a clean env.
$outFile = Join-Path $env:TEMP 'pocket-tunnel-out.log'
$errFile = Join-Path $env:TEMP 'pocket-tunnel-err.log'
Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue

$saved = @{}
foreach ($k in 'HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy', 'ALL_PROXY', 'all_proxy') {
    $saved[$k] = [Environment]::GetEnvironmentVariable($k)
    [Environment]::SetEnvironmentVariable($k, $null)
}
try {
    $proc = Start-Process -FilePath $exe `
        -ArgumentList '--no-autoupdate', 'tunnel', '--url', "http://127.0.0.1:$Port", '--protocol', 'quic' `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
        -PassThru -WindowStyle Hidden
} finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
}

Write-Host "cloudflared pid $($proc.Id), waiting for the assigned hostname..."

# --- scrape the URL ----------------------------------------------------------
$url = $null
for ($i = 0; $i -lt $TimeoutSeconds; $i++) {
    Start-Sleep -Seconds 1
    foreach ($f in $outFile, $errFile) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $m = Select-String -Path $f -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches -ErrorAction SilentlyContinue
        if ($m) {
            $url = $m[0].Matches[0].Value
            break
        }
    }
    if ($url) { break }
    if ($proc.HasExited) { break }
}

if (-not $url) {
    Write-Host 'ERROR: no trycloudflare hostname appeared. cloudflared output:' -ForegroundColor Red
    foreach ($f in $outFile, $errFile) {
        if (Test-Path -LiteralPath $f) { Get-Content $f -Tail 20 }
    }
    if (-not $proc.HasExited) { $proc.Kill() }
    exit 2
}

Write-Host ''
Write-Host "POCKET URL: $url" -ForegroundColor Green
if ($PocketToken) { Write-Host "password : $PocketToken" -ForegroundColor Green }

# --- QR ----------------------------------------------------------------------
if ($QrPath) {
    $qrMod = $null
    foreach ($c in @(
            (Join-Path $env:USERPROFILE '.dsh\profiles\desktop\node_modules\qrcode'),
            (Join-Path $env:USERPROFILE '.dsh\profiles\web\node_modules\qrcode')
        )) { if (Test-Path -LiteralPath $c) { $qrMod = $c; break } }

    if ($qrMod) {
        $js = Join-Path $env:TEMP 'pocket-qr.cjs'
        @'
const QRCode = require(process.argv[2]);
QRCode.toFile(process.argv[3], process.argv[4], { width: 640, margin: 2 })
  .then(() => console.log('ok'))
  .catch((e) => { console.error(e.message); process.exit(1); });
'@ | Set-Content -LiteralPath $js -Encoding utf8
        $target = if ($PocketToken) { "$url/?token=$PocketToken" } else { $url }
        & (Get-Command node).Source $js $qrMod $QrPath $target 2>&1 | Out-Null
        if (Test-Path -LiteralPath $QrPath) { Write-Host "QR written: $QrPath" -ForegroundColor Green }
    } else {
        Write-Host 'WARN: qrcode module not found; skipping QR' -ForegroundColor Yellow
    }
}

# --- state file --------------------------------------------------------------
# The watcher (pocket-tunnel-ensure.ps1) reads this to decide whether the URL
# still answers, so it must be written after the hostname is proven capturable.
if ($StateFile) {
    $state = [ordered]@{
        url       = $url
        target    = if ($PocketToken) { "$url/?token=$PocketToken" } else { $url }
        port      = $Port
        pid       = $proc.Id
        startedAt = (Get-Date).ToString('o')
    }
    ($state | ConvertTo-Json) | Set-Content -LiteralPath $StateFile -Encoding utf8
    Write-Host "state written: $StateFile" -ForegroundColor Green
}

# --- keep alive --------------------------------------------------------------
if ($KeepRunning) {
    Write-Host 'Tunnel stays in the foreground. Ctrl+C stops it.'
    $proc.WaitForExit()
} else {
    Write-Host ''
    Write-Host "Tunnel is running detached (pid $($proc.Id)). Stop it with: Stop-Process -Id $($proc.Id)"
}

exit 0


