# Pin dsh-pocket's access PIN so it stops rotating.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File set-pocket-pin.ps1 -Pin YourPin12345
#   ... -Which lan          # pin the LAN PIN instead of the public one
#
# Why: by default the PUBLIC pin is regenerated every time a Quick Tunnel becomes
# ready (rotateAccessToken in the plugin). A QR scanned two minutes earlier then
# fails with 瀵嗙爜閿欒 and nothing looks wrong. Writing the pin together with the
# corresponding *PinCustom flag turns rotation into a no-op.
#
# Rules from the plugin: 8-64 characters, letters and digits only.

param(
    [Parameter(Mandatory = $true)]
    [string]$Pin,
    [ValidateSet('public', 'lan')]
    [string]$Which = 'public',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Say($m) { Write-Host $m }
function Die($m) { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

if ($Pin.Length -lt 8 -or $Pin.Length -gt 64 -or $Pin -notmatch '^[A-Za-z0-9]+$') {
    Die 'PIN must be 8-64 characters, letters and digits only'
}

$dir = Join-Path $env:USERPROFILE '.dsh\dsh-pocket'
if (-not (Test-Path -LiteralPath $dir)) { Die "dsh-pocket has never run; $dir is missing. Start DSH once first." }

# The two PINs live in separate files and are checked separately: a public
# (tunnel) URL never accepts the LAN pin and vice versa.
$tokenFile = if ($Which -eq 'lan') { Join-Path $dir 'token-lan' } else { Join-Path $dir 'token' }
$settingsFile = Join-Path $dir 'settings.json'
$flag = if ($Which -eq 'lan') { 'lanPinCustom' } else { 'publicPinCustom' }

# Refuse to overwrite a pin the user did not ask us to touch.
if (Test-Path -LiteralPath $tokenFile) {
    $current = (Get-Content -LiteralPath $tokenFile -Raw).Trim()
    if ($current -and $current -ne $Pin) { Say "overwriting existing $Which pin ($($current.Length) chars, value hidden)" }
}

if ($DryRun) {
    Say "DRY RUN 鈥?would set $Which pin to '$Pin' and $flag=true"
    exit 0
}

# Keep a copy of the previous value so a mistake is recoverable.
if (Test-Path -LiteralPath $tokenFile) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item -LiteralPath $tokenFile -Destination "$tokenFile.bak-$stamp" -Force
}

Set-Content -LiteralPath $tokenFile -Value $Pin -NoNewline -Encoding ascii

# Merge into settings.json without dropping keys the plugin already stored
# (tunnelMode / tunnelToken / tunnelHostname live here too).
$settings = [ordered]@{}
if (Test-Path -LiteralPath $settingsFile) {
    try {
        $raw = Get-Content -LiteralPath $settingsFile -Raw
        if ($raw.Trim()) {
            $existing = $raw | ConvertFrom-Json
            foreach ($p in $existing.PSObject.Properties) { $settings[$p.Name] = $p.Value }
        }
    } catch {
        Say "WARN: settings.json was unreadable, rebuilding it: $($_.Exception.Message)"
    }
}
$settings[$flag] = $true
($settings | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $settingsFile -Encoding utf8

Say "set $Which pin = $Pin"
Say "settings: $(Get-Content -LiteralPath $settingsFile -Raw)"
Say ''
Say 'Restart DSH for the plugin to reload it:'
Say '  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\restart-dsh.ps1'

