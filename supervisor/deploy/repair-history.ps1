# Audit the journal against the brokers once, then re-arm only the gaps.
#
# `reset-host.ps1` registers this as a one-shot task after a rebuild, because the
# audit is only meaningful once the fleet has finished its first pass: run it
# before that and every account looks like it is missing every trade. This script
# waits for that, stops the supervisor, runs `verify_history.py --repair`, starts
# the supervisor again, and removes its own task.
#
# Run it by hand to do the same thing at any other time:
#
#   powershell -ExecutionPolicy Bypass -File C:\MTLSync\repair-history.ps1
#   ... -Now              # do not wait for the fleet to settle
#   ... -Days 3650        # audit the deep window instead of BACKFILL_DAYS
#   ... -MaxWaitMinutes 0 # give up waiting immediately
#
# "Settled" means: no `.backfill` marker is left, and every live connection has a
# `last_sync_at` within `-SettleMinutes`. A connection stuck on a bad password
# never settles, so the wait is capped by `-MaxWaitMinutes` and the audit then
# runs on whatever is there, reporting that account as an error instead of a gap.

param(
    [string]$Root = 'C:\MTLSync',
    [string]$TaskName = 'MTL Ledger Sync Supervisor',
    # Set by reset-host.ps1 when it registers this as a task: the name to remove
    # when the run is over. Empty means this was run by hand.
    [string]$SelfTask = '',
    [int]$Days = 0,
    [int]$SettleMinutes = 15,
    [int]$MaxWaitMinutes = 600,
    [int]$PollSeconds = 60,
    [string]$Python = '',
    [switch]$Now
)

$ErrorActionPreference = 'Stop'

function Read-EnvMap([string]$Path) {
    $map = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*#' -or $line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') { continue }
        $map[$Matches[1]] = $Matches[2].Trim().Trim('"')
    }
    return $map
}

$EnvPath = Join-Path $Root '.env'
if (-not (Test-Path -LiteralPath $EnvPath)) {
    throw "No .env at $EnvPath. The audit needs the same keys the supervisor uses."
}
$envMap = Read-EnvMap $EnvPath
foreach ($key in 'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY') {
    if (-not $envMap.ContainsKey($key) -or -not $envMap[$key]) {
        throw "$key is empty in $EnvPath, so the fleet cannot be checked."
    }
}

$verifier = Join-Path $Root 'verify_history.py'
if (-not (Test-Path -LiteralPath $verifier)) {
    throw "No verify_history.py in $Root. Copy the supervisor folder there first."
}

if ($Days -le 0) {
    $Days = 365
    if ($envMap['BACKFILL_DAYS'] -match '^\d+$') { $Days = [int]$envMap['BACKFILL_DAYS'] }
}

if (-not $Python) {
    $Python = 'C:\Program Files\Python312\python.exe'
    if (-not (Test-Path -LiteralPath $Python)) {
        $found = Get-Command python.exe -ErrorAction SilentlyContinue
        if ($found) { $Python = $found.Source }
    }
}
if (-not (Test-Path -LiteralPath $Python)) {
    throw 'Python was not found. Pass -Python with the interpreter reset-host.ps1 used.'
}

$url = $envMap['SUPABASE_URL'].TrimEnd('/')
$key = $envMap['SUPABASE_SERVICE_ROLE_KEY']

function Get-PendingReads {
    @(Get-ChildItem -LiteralPath (Join-Path $Root '.backfill') -Filter '*.json' -Force -ErrorAction SilentlyContinue)
}

# The connections the supervisor is supposed to be driving, and when each last
# reached the broker. Null or old `last_sync_at` is work still to do.
function Get-Unsettled {
    $uri = '{0}/rest/v1/broker_connections?select=id,status,last_sync_at&status=neq.disconnected' -f $url
    $headers = @{ apikey = $key; Authorization = "Bearer $key" }
    $connections = @(Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -TimeoutSec 20)
    $floor = (Get-Date).ToUniversalTime().AddMinutes(-$SettleMinutes)
    @($connections | Where-Object {
        if ($_.status -eq 'pending' -or -not $_.last_sync_at) {
            $true
        } else {
            try { ([datetimeoffset]::Parse([string]$_.last_sync_at)).UtcDateTime -lt $floor } catch { $true }
        }
    })
}

Write-Host ''
Write-Host 'Audit the journal against the brokers' -ForegroundColor Cyan
Write-Host ("  host folder : {0}" -f $Root)
Write-Host ("  window      : {0} day(s)" -f $Days)
Write-Host ("  supervisor  : task '{0}', stopped during the audit and started again" -f $TaskName)
Write-Host ''

if (-not $Now) {
    $deadline = (Get-Date).AddMinutes($MaxWaitMinutes)
    while ($true) {
        $pending = Get-PendingReads
        $unsettled = @()
        $checked = $true
        try {
            $unsettled = Get-Unsettled
        } catch {
            $checked = $false
            Write-Host ("  cannot reach Supabase yet ({0}); waiting" -f $_.Exception.Message) -ForegroundColor DarkGray
        }
        if ($checked -and $pending.Count -eq 0 -and $unsettled.Count -eq 0) {
            Write-Host 'The fleet has settled; auditing now.' -ForegroundColor DarkGray
            break
        }
        if ((Get-Date) -ge $deadline) {
            Write-Host (("Waited {0} minute(s). Auditing anyway: {1} history read(s) still running, {2} connection(s) not settled.") -f
                $MaxWaitMinutes, $pending.Count, $unsettled.Count) -ForegroundColor Yellow
            break
        }
        Write-Host ("  waiting: {0} history read(s) running, {1} connection(s) without a sync in the last {2} minute(s)" -f
            $pending.Count, $unsettled.Count, $SettleMinutes)
        Start-Sleep -Seconds $PollSeconds
    }
}

# --- Stop the fleet, audit, start it again ----------------------------------

Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$logs = Join-Path $Root 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$logFile = Join-Path $logs ('repair-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$repairFile = Join-Path $Root 'repair-history.json'

$code = -1
try {
    # Captured rather than teed: `Tee-Object` writes UTF-16 on PowerShell 5.1,
    # which leaves NUL bytes in a log that tail and grep should read plainly.
    $output = & $Python $verifier --days $Days --repair --repair-file $repairFile 2>&1
    $code = $LASTEXITCODE
    $output | Out-File -LiteralPath $logFile -Encoding utf8
    $output | Write-Host
} finally {
    Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
}

$queued = 0
if (Test-Path -LiteralPath $repairFile) {
    try { $queued = @((Get-Content -LiteralPath $repairFile -Raw | ConvertFrom-Json).repairs).Count } catch { $queued = 0 }
}

Write-Host ''
if ($code -eq 0) {
    Write-Host 'Audit passed: the journal matches the brokers.' -ForegroundColor Green
} elseif ($code -eq 1) {
    Write-Host ("Audit found gaps; {0} account(s) queued to re-read. They fill on the next cycle." -f $queued) -ForegroundColor Yellow
} else {
    Write-Host ("verify_history.py exited with code {0}; see {1}" -f $code, $logFile) -ForegroundColor Red
}
Write-Host ("  log     : {0}" -f $logFile)
Write-Host ("  repairs : {0}" -f $(if (Test-Path -LiteralPath $repairFile) { $repairFile } else { '(none written)' }))
Write-Host ("  fleet   : task '{0}' started again" -f $TaskName)

if ($SelfTask) {
    Unregister-ScheduledTask -TaskName $SelfTask -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host ("  removed the one-shot task '{0}'" -f $SelfTask)
}

exit $(if ($code -ge 2) { 1 } else { 0 })
