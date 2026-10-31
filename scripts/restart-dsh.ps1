# Restart the DSH desktop app and wait for its web port to come back.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File restart-dsh.ps1
#   ... -Exe 'D:\DSH-O\DeepSeek Harness.exe' -HoldSeconds 40
#
# Launch this through WMI so it survives killing the app tree:
#   Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
#     CommandLine = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<this file>"'
#   }
# A child of the current shell dies with the app; a WmiPrvSE child does not, and
# it still runs in the interactive session so the relaunched window is visible.

param(
    [string]$Exe = '',
    [int]$HoldSeconds = 40,
    [string]$LogFile = ''
)

$ErrorActionPreference = 'Continue'
if (-not $LogFile) { $LogFile = Join-Path $env:TEMP 'dsh-restart.log' }

function Log([string]$m) {
    '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m |
        Out-File -LiteralPath $LogFile -Append -Encoding utf8
}

# Discover the executable from the running app when -Exe is omitted.
if (-not $Exe) {
    $running = Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($running -and $running.Path) { $Exe = $running.Path }
}
if (-not $Exe -or -not (Test-Path -LiteralPath $Exe)) {
    Log "ERROR: cannot find the DSH executable; pass -Exe '<path to DeepSeek Harness.exe>'"
    exit 4
}

function AppProcs {
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Exe }
}

function WebPort {
    $pids = (AppProcs).Id
    if (-not $pids) { return 0 }
    $ports = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $pids -contains $_.OwningProcess } |
        Select-Object -ExpandProperty LocalPort -Unique
    foreach ($p in $ports) {
        try {
            $r = Invoke-WebRequest "http://127.0.0.1:$p/mgw/status" -UseBasicParsing -TimeoutSec 2
            if ($r.StatusCode -eq 200) { return $p }
        } catch { }
    }
    return 0
}

Log '=== restart started ==='
Log "app pids before: $((AppProcs | ForEach-Object Id) -join ',')"
Log "holding ${HoldSeconds}s so the current turn can finish"
Start-Sleep -Seconds $HoldSeconds

$deadline = (Get-Date).AddSeconds(40)
while ((AppProcs) -and (Get-Date) -lt $deadline) {
    AppProcs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
}
if (AppProcs) { Log 'ERROR: processes survived; not relaunching'; exit 1 }
Log 'all app processes stopped'

Start-Sleep -Seconds 1
try { Start-Process -FilePath $Exe -WorkingDirectory (Split-Path $Exe) | Out-Null }
catch { Log "ERROR: relaunch failed: $($_.Exception.Message)"; exit 2 }
Log 'relaunch issued'

# The web port is random each start, so poll for ANY port answering /mgw/status
# rather than a fixed one. If the gateway plugin is absent, fall back to any
# listening port and just report it.
$found = 0
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 1
    $found = WebPort
    if ($found) { break }
}
if (-not $found) {
    Log 'gateway did not answer within 90s; retrying once'
    AppProcs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Process -FilePath $Exe -WorkingDirectory (Split-Path $Exe) | Out-Null
    for ($i = 0; $i -lt 90; $i++) {
        Start-Sleep -Seconds 1
        $found = WebPort
        if ($found) { break }
    }
}
if (-not $found) { Log 'ERROR: web port never answered'; exit 3 }
Log "web port: $found"

$main = AppProcs | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($main) { Log "window pid $($main.Id) title=$($main.MainWindowTitle)" }
else { Log 'WARN: no main window handle yet' }

Log '=== restart finished ==='
exit 0
