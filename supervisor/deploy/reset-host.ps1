# Wipe this sync host and rebuild it, keeping C:\MTLSync\.env exactly as it is.
#
# The expensive part of a wiped host is not the terminal, it is `.env`: its
# SYNC_CREDENTIAL_KEY decrypts every customer's stored password, so losing it
# means all of them retype one. This script therefore reads `.env` first, copies
# it to a place the wipe cannot reach, rebuilds everything around it, and checks
# the hash before and after. It never edits the file.
#
#   powershell -ExecutionPolicy Bypass -File C:\MTL\supervisor\deploy\reset-host.ps1
#
# Then, once the files are back, it re-registers the task and starts it. Add
# `-Verify` to run one `--once` pass first (that pass can take an hour per
# account when the history depth is years, so it is off by default).
#
# `-DeepHistoryDays 3650` re-arms a from-scratch read for every live connection
# through the Supabase REST API, which is what makes the rebuild recover old
# trades instead of resuming from each account's cursor. It refuses to run if
# `.env` still says `BACKFILL_DAYS` lower than that: the script will not change
# the file, so set the value yourself and run it again.
#
# What is kept: `.env`, the supervisor code and the deploy scripts (restored from
# this folder or from the copy this script was run from), `mt5-brokers.json`,
# and a `servers.dat` found in the host folder, which a fresh terminal needs to
# resolve prop-firm servers. Everything else under the host folder, every
# terminal directory and every fleet slot is deleted. Logs and `.backfill`
# markers go with them: that is the point of a wipe.
#
# Never deleted: a terminal under Program Files. When `MT5_PATH` points there,
# that install is treated as the source of the copies, not as a slot.

param(
    [string]$Root = 'C:\MTLSync',
    # The folder holding mt5_supervisor.py. Defaults to the parent of this
    # script's folder, so running it from C:\MTL\supervisor\deploy works, and so
    # does running a copy that was unzipped into C:\MTLSync.
    [string]$Source = '',
    [string]$TerminalSource = 'C:\Program Files\MetaTrader 5',
    [string]$TaskName = 'MTL Ledger Sync Supervisor',
    [int]$DeepHistoryDays = 0,
    [switch]$Verify,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this in an elevated PowerShell (Run as Administrator): it deletes directories and re-registers a task.'
}

function Read-EnvMap([string]$Path) {
    $map = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*#' -or $line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') { continue }
        $map[$Matches[1]] = $Matches[2].Trim().Trim('"')
    }
    return $map
}

# --- What we are about to do ------------------------------------------------

$EnvPath = Join-Path $Root '.env'
if (-not (Test-Path -LiteralPath $EnvPath)) {
    throw "No .env at $EnvPath. This script keeps that file, so it has to exist before the wipe. Run setup_vps.ps1 first."
}
$envMap = Read-EnvMap $EnvPath
foreach ($key in 'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'SYNC_CREDENTIAL_KEY', 'SYNC_SUPERVISOR_TOKEN') {
    if (-not $envMap.ContainsKey($key) -or -not $envMap[$key]) {
        throw "$key is empty in $EnvPath. The host cannot run without it, and this script will not invent one."
    }
}

if (-not $Source) {
    $Source = Split-Path $PSScriptRoot -Parent
}
if (-not (Test-Path -LiteralPath (Join-Path $Source 'mt5_supervisor.py'))) {
    throw "No mt5_supervisor.py in '$Source'. Pass -Source with the folder that holds it (C:\MTL\supervisor)."
}
$Source = (Resolve-Path -LiteralPath $Source).Path
$brokersFile = Join-Path $Source 'mt5-brokers.json'
if (-not (Test-Path -LiteralPath $brokersFile)) {
    $brokersFile = Join-Path (Split-Path $Source -Parent) 'shared\mt5-brokers.json'
}
if (-not (Test-Path -LiteralPath $brokersFile)) {
    throw "No mt5-brokers.json beside '$Source' or in its sibling shared\ folder."
}

# The terminal the host logs in through, and the fleet slots it holds open. Both
# are copies; the Program Files install they came from is never a target.
$terminalDest = ''
if ($envMap['MT5_PATH']) {
    $terminalDest = Split-Path $envMap['MT5_PATH'] -Parent
    if ($terminalDest -like '*\Program Files*') {
        Write-Host "MT5_PATH points inside Program Files; that install is the source and is left alone." -ForegroundColor Yellow
        $terminalDest = ''
    }
}

$fleetDirs = @()
if ($envMap['MT5_FLEET_DIRS']) {
    $fleetDirs = $envMap['MT5_FLEET_DIRS'] -split '[,;]' |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ } |
        ForEach-Object { if ($_ -match '\.exe$') { Split-Path $_ -Parent } else { $_ } } |
        Sort-Object -Unique
}
$fleetSize = 0
if ($envMap['FLEET_SIZE'] -match '^\d+$') { $fleetSize = [int]$envMap['FLEET_SIZE'] }

if ($DeepHistoryDays -gt 0) {
    $configured = 0
    if ($envMap['BACKFILL_DAYS'] -match '^\d+$') { $configured = [int]$envMap['BACKFILL_DAYS'] }
    if ($configured -lt $DeepHistoryDays) {
        throw ("BACKFILL_DAYS=$configured in .env, but -DeepHistoryDays $DeepHistoryDays needs at least that. " +
            "This script does not edit .env: change the line to BACKFILL_DAYS=$DeepHistoryDays and run it again.")
    }
}

$envHash = (Get-FileHash -LiteralPath $EnvPath -Algorithm SHA256).Hash

Write-Host ''
Write-Host 'Wipe and rebuild the sync host' -ForegroundColor Cyan
Write-Host ("  host folder : {0}" -f $Root)
Write-Host ("  code from   : {0}" -f $Source)
Write-Host ("  terminal    : {0}" -f $(if ($terminalDest) { $terminalDest } else { '(none - Program Files install is used as-is)' }))
Write-Host ("  fleet slots : {0}" -f $(if ($fleetDirs.Count) { "$($fleetDirs.Count) under $(Split-Path $fleetDirs[0] -Parent)" } else { 'none' }))
Write-Host ("  .env        : kept, SHA256 {0}" -f $envHash)
Write-Host ("  history     : BACKFILL_DAYS={0}{1}" -f $envMap['BACKFILL_DAYS'], $(if ($DeepHistoryDays) { ", re-arm every live connection" } else { '' }))
Write-Host ''
Write-Host 'Deleted: the host folder, its logs and .backfill markers, and every terminal copy above.'
Write-Host ''

if (-not $Yes) {
    $answer = Read-Host "Type WIPE to continue"
    if ($answer -ne 'WIPE') { throw 'Aborted. Nothing was changed.' }
}

# --- Keep what the wipe would destroy ---------------------------------------

# Staged outside the host folder, because the code being copied may live inside
# it: a copy unzipped into C:\MTLSync would otherwise delete its own source.
$stage = Join-Path $env:TEMP "mtlsync-reset-$stamp"
New-Item -ItemType Directory -Force -Path $stage | Out-Null

Copy-Item -LiteralPath $EnvPath -Destination (Join-Path $stage '.env') -Force
Copy-Item -LiteralPath (Join-Path $Source 'mt5_supervisor.py') -Destination $stage -Force
Copy-Item -LiteralPath $brokersFile -Destination $stage -Force
foreach ($name in 'run-supervisor.ps1', 'register-task.ps1') {
    $path = Join-Path (Join-Path $Source 'deploy') $name
    if (-not (Test-Path -LiteralPath $path)) { $path = Join-Path $Source $name }
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing $name in '$Source\deploy'. Re-copy the supervisor folder first." }
    Copy-Item -LiteralPath $path -Destination $stage -Force
}
$stagedServers = Join-Path $Root 'servers.dat'
if (Test-Path -LiteralPath $stagedServers) { Copy-Item -LiteralPath $stagedServers -Destination $stage -Force }

$stagedHash = (Get-FileHash -LiteralPath (Join-Path $stage '.env') -Algorithm SHA256).Hash
if ($stagedHash -ne $envHash) { throw 'The .env copy does not match the original. Nothing was changed.' }

# A second copy outside %TEMP%, so a cleanup of temp files cannot take the only
# remaining key with it.
$backupDir = Join-Path $(if ($env:ProgramData) { $env:ProgramData } else { 'C:\ProgramData' }) 'MTLSync'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$backup = Join-Path $backupDir "env-$stamp.bak"
Copy-Item -LiteralPath $EnvPath -Destination $backup -Force
Write-Host ("Staged {0} and backed up .env to {1}" -f $stage, $backup) -ForegroundColor DarkGray

# --- Stop everything that could hold a file open ----------------------------

Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like '*mt5_supervisor.py*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process terminal64 -ErrorAction SilentlyContinue | Wait-Process -Timeout 20 -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# --- Wipe -------------------------------------------------------------------

foreach ($dir in @($Root) + $fleetDirs) {
    if (Test-Path -LiteralPath $dir) {
        Remove-Item -LiteralPath $dir -Recurse -Force
        Write-Host "deleted $dir" -ForegroundColor DarkGray
    }
}
if ($terminalDest -and (Test-Path -LiteralPath $terminalDest)) {
    Remove-Item -LiteralPath $terminalDest -Recurse -Force
    Write-Host "deleted $terminalDest" -ForegroundColor DarkGray
}

# --- Rebuild ----------------------------------------------------------------

New-Item -ItemType Directory -Force -Path $Root | Out-Null
foreach ($name in '.env', 'mt5_supervisor.py', 'mt5-brokers.json', 'run-supervisor.ps1', 'register-task.ps1') {
    $from = Join-Path $stage $name
    if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination $Root -Force }
}
$restoredHash = (Get-FileHash -LiteralPath (Join-Path $Root '.env') -Algorithm SHA256).Hash
if ($restoredHash -ne $envHash) { throw "The restored .env does not match the original. A copy is at $backup, and the staged one at $stage." }
Write-Host "restored $Root with .env unchanged" -ForegroundColor DarkGray

if ($terminalDest) {
    if (-not (Test-Path -LiteralPath (Join-Path $TerminalSource 'terminal64.exe'))) {
        throw "No terminal64.exe in '$TerminalSource'. Pass -TerminalSource with the install to copy."
    }
    Copy-Item -LiteralPath $TerminalSource -Destination $terminalDest -Recurse -Force
    if (Test-Path -LiteralPath (Join-Path $stage 'servers.dat')) {
        $config = Join-Path $terminalDest 'config'
        New-Item -ItemType Directory -Force -Path $config | Out-Null
        Copy-Item -LiteralPath (Join-Path $stage 'servers.dat') -Destination (Join-Path $config 'servers.dat') -Force
    }
    Write-Host "copied the terminal to $terminalDest" -ForegroundColor DarkGray
}

if ($fleetSize -gt 0) {
    $setupFleet = Join-Path $Source 'setup_fleet.ps1'
    if (-not (Test-Path -LiteralPath $setupFleet)) {
        Write-Host "FLEET_SIZE=$fleetSize but setup_fleet.ps1 is not in '$Source'; prepare the slots by hand." -ForegroundColor Yellow
    } else {
        $fleetRoot = if ($fleetDirs.Count) { Split-Path $fleetDirs[0] -Parent } else { 'C:\MT5-Fleet' }
        $fleetArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $setupFleet,
            '-Count', $fleetSize, '-Root', $fleetRoot, '-Source', $TerminalSource)
        if (Test-Path -LiteralPath (Join-Path $stage 'servers.dat')) {
            $fleetArgs += @('-ServersFrom', (Join-Path $stage 'servers.dat'))
        }
        & powershell.exe @fleetArgs
        if ($LASTEXITCODE -ne 0) { throw "setup_fleet.ps1 failed with exit code $LASTEXITCODE." }
        if ($fleetDirs.Count -ne $fleetSize) {
            Write-Host "FLEET_SIZE=$fleetSize but MT5_FLEET_DIRS lists $($fleetDirs.Count) slot(s). Update .env to the MT5_FLEET_DIRS line above." -ForegroundColor Yellow
        }
    }
}

$python = 'C:\Program Files\Python312\python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    $found = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($found) { $python = $found.Source }
}
if (-not (Test-Path -LiteralPath $python)) {
    Write-Host 'Python 3.12 is not installed; run setup_vps.ps1, then this script again.' -ForegroundColor Yellow
    $python = ''
} else {
    & $python -c "import MetaTrader5, requests, dotenv" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Python at $python cannot import MetaTrader5/requests/dotenv; run setup_vps.ps1 to reinstall them." -ForegroundColor Yellow
    }
}

if ($DeepHistoryDays -gt 0) {
    $key = $envMap['SUPABASE_SERVICE_ROLE_KEY']
    $uri = '{0}/rest/v1/broker_connections?status=neq.disconnected' -f $envMap['SUPABASE_URL'].TrimEnd('/')
    $headers = @{
        apikey        = $key
        Authorization = "Bearer $key"
        'Content-Type' = 'application/json'
        Prefer        = 'return=minimal'
    }
    $body = @{ status = 'pending'; last_sync_at = $null; last_error = $null } | ConvertTo-Json
    Invoke-RestMethod -Method Patch -Uri $uri -Headers $headers -Body $body | Out-Null
    Write-Host ("Re-armed every live connection for a {0}-day read." -f $DeepHistoryDays) -ForegroundColor DarkGray
}

if ($Verify) {
    if (-not $python) { throw 'Cannot verify without Python.' }
    Write-Host 'Running one pass (this can take hours at a deep history depth)...' -ForegroundColor Cyan
    & $python (Join-Path $Root 'mt5_supervisor.py') --once
    Write-Host ("--once exited with code {0}" -f $LASTEXITCODE)
}

if (-not $python) {
    throw 'Python is missing, so the task was not registered. Run setup_vps.ps1 and register-task.ps1 once Python is back.'
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'register-task.ps1') `
    -TaskName $TaskName `
    -Wrapper (Join-Path $Root 'run-supervisor.ps1') `
    -Python $python

Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue

Get-ScheduledTask -TaskName $TaskName | Select-Object TaskName, State
Start-Sleep -Seconds 10
$log = Join-Path $Root 'logs\supervisor.log'
if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 10 }

Write-Host ''
Write-Host ("Done. .env unchanged (SHA256 {0}); backup at {1}" -f $envHash, $backup) -ForegroundColor Green
if ($DeepHistoryDays -gt 0) {
    Write-Host ("The {0}-day read is filling in the background. Put BACKFILL_DAYS back to 365 when the counts stop moving." -f $DeepHistoryDays) -ForegroundColor Yellow
}
Write-Host ("Log: {0}" -f $log) -ForegroundColor Cyan
