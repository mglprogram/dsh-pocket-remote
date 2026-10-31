# Install / repair dsh-pocket so a phone can open the real DSH UI.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File install-pocket.ps1
#   ... -Profile web -Version latest -DryRun
#
# Idempotent: re-run after a plugin upgrade or when the 手机访问 entry is missing.
# Handles the two traps that silently break installation — a local socks proxy
# making pnpm hang, and the plugin manager failing to write the bundle row.

param(
    [string]$Profile = 'desktop',
    [string]$Version = 'latest',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Say($m) { Write-Host $m }
function Die($m) { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# --- locate the profile -------------------------------------------------------
$profileDir = Join-Path $env:USERPROFILE ".dsh\profiles\$Profile"
if (-not (Test-Path -LiteralPath $profileDir)) { Die "profile not found: $profileDir" }
$pkgPath = Join-Path $profileDir 'package.json'
Say "profile: $profileDir"

# --- locate pnpm --------------------------------------------------------------
# DSH bundles its own pnpm under <install>\resources\runtime\...\pnpm\bin\pnpm.mjs.
# Prefer that one (version-matched to the runtime), then PATH.
function Find-Pnpm {
    $roots = @()
    $proc = Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.Path) { $roots += (Split-Path $proc.Path) }
    $roots += 'E:\DSH-O', 'C:\Program Files\DSH', (Join-Path $env:LOCALAPPDATA 'Programs\DSH')
    foreach ($root in $roots) {
        $hit = Get-ChildItem (Join-Path $root 'resources\runtime') -Filter 'pnpm.mjs' -Recurse -Depth 4 -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    $cmd = Get-Command pnpm -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$pnpm = Find-Pnpm
if (-not $pnpm) { Die 'pnpm not found; start DSH once so its bundled runtime exists, or install pnpm' }
Say "pnpm: $pnpm"

$spec = if ($Version -eq 'latest') { 'dsh-pocket@latest' } else { "dsh-pocket@$Version" }

if ($DryRun) {
    Say ''
    Say 'DRY RUN — nothing written. Would:'
    Say "  pnpm add $spec"
    Say "  ensure bundles row 'dsh-pocket'"
    Say '  print the next steps'
    exit 0
}

# --- install ----------------------------------------------------------------
# Clear the proxy for this call only: a socks5 HTTP_PROXY makes pnpm hang for
# minutes and then fail with ERR_PNPM_META_FETCH_FAIL, while npm and node fetch
# work fine through the same proxy.
$saved = @{}
foreach ($k in 'HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy', 'ALL_PROXY', 'all_proxy') {
    $saved[$k] = [Environment]::GetEnvironmentVariable($k)
    [Environment]::SetEnvironmentVariable($k, $null)
}
try {
    Push-Location $profileDir
    try {
        & (Get-Command node).Source $pnpm add $spec --reporter=append-only
        if ($LASTEXITCODE -ne 0) { Die "pnpm add failed (exit $LASTEXITCODE)" }
    } finally { Pop-Location }
} finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
}

# --- ensure the bundle row ---------------------------------------------------
# The plugin manager sometimes reports a registry error and skips writing this
# row even though the package landed. Without the row the plugin never loads and
# the 手机访问 entry never appears in Settings.
$manifest = Get-Content -LiteralPath $pkgPath -Raw | ConvertFrom-Json
$bundles = @($manifest.dsh.profile.bundles)
if ($bundles -notcontains 'dsh-pocket') {
    $updated = @()
    $inserted = $false
    foreach ($b in $bundles) {
        $updated += $b
        if (-not $inserted -and $b -eq '@deepseek-ai/dsh-web-app') {
            $updated += 'dsh-pocket'
            $inserted = $true
        }
    }
    if (-not $inserted) { $updated += 'dsh-pocket' }
    $manifest.dsh.profile.bundles = $updated
    ($manifest | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $pkgPath -Encoding utf8
    Say 'added bundle row dsh-pocket'
} else {
    Say 'bundle row already present'
}

# --- report the installed version -------------------------------------------
$installed = $null
$pj = Join-Path $profileDir 'node_modules\dsh-pocket\package.json'
if (Test-Path -LiteralPath $pj) {
    $installed = (Get-Content -LiteralPath $pj -Raw | ConvertFrom-Json).version
}
Say "dsh-pocket on disk: $installed"

Say ''
Say 'Next:'
Say '  1. Restart DSH (the plugin JS loads at host start):'
Say '       powershell -NoProfile -ExecutionPolicy Bypass -File scripts\restart-dsh.ps1'
Say '  2. Pin the public PIN so it stops rotating:'
Say '       powershell -NoProfile -ExecutionPolicy Bypass -File scripts\set-pocket-pin.ps1 -Pin <8-64 letters/digits>'
Say '  3. Restart DSH again, then 设置 → 手机访问 → scan the QR shown there.'
