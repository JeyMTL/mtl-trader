# One-shot install of a sync host from this folder.
#
# Copy the whole `supervisor` folder and its sibling `shared\mt5-brokers.json` to
# C:\MTL, then in an elevated PowerShell:
#
#   powershell -ExecutionPolicy Bypass -File C:\MTL\supervisor\deploy\install-host.ps1
#
# It asks only for the secrets that are missing, with hidden input (nothing is
# echoed, so a screenshot cannot capture them), writes C:\MTLSync\.env, installs
# Python and MetaTrader 5 if they are absent, prepares the fleet slots, rebuilds
# the host through reset-host.ps1, and starts the task.
#
#   -FleetSize 18            slots to prepare (default 4; 18 on the 8 GB host)
#   -BackfillDays 3650       how far a first sync reads (default 3650)
#   -DeepHistoryDays 3650    re-arm every live connection, same window
#   -RotateSecrets           prompt again even when .env already has values
#   -SkipRebuild             install and stop before anything is deleted
#   -DryRun                  print the plan and the settings, change nothing
#
# This script owns .env. reset-host.ps1 only preserves it, so a secret typed here
# is never rewritten or asked for again by the steps below it.

param(
    [string]$Root = 'C:\MTLSync',
    [int]$FleetSize = 4,
    [int]$BackfillDays = 3650,
    [int]$DeepHistoryDays = 3650,
    [string]$TerminalSource = 'C:\Program Files\MetaTrader 5',
    [switch]$RotateSecrets,
    [switch]$SkipRebuild,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Say($message) { Write-Host "==> $message" -ForegroundColor Cyan }

$Source = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path -LiteralPath (Join-Path $Source 'mt5_supervisor.py'))) {
    throw "No mt5_supervisor.py in '$Source'. Run this from the supervisor\deploy folder."
}
$EnvPath = Join-Path $Root '.env'
$fleetRoot = 'C:\MT5-Fleet'
$secretKeys = @('SUPABASE_SERVICE_ROLE_KEY', 'SYNC_CREDENTIAL_KEY', 'SYNC_SUPERVISOR_TOKEN')

function Format-Env([hashtable]$Map) {
    $order = @(
        'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'SYNC_CREDENTIAL_KEY', 'SYNC_SUPERVISOR_TOKEN',
        'APP_URL', 'MT5_PATH', 'MT5_PATHS', 'MT5_PORTABLE', 'MT5_FLEET_DIRS', 'FLEET_SIZE',
        'WATCH_SECONDS', 'LOCK_POLL_SECONDS', 'ENFORCE_LOCK', 'BACKFILL_DAYS'
    )
    $lines = @()
    foreach ($key in $order) {
        if ($Map.ContainsKey($key) -and $Map[$key]) { $lines += "$key=$($Map[$key])" }
    }
    foreach ($key in ($Map.Keys | Sort-Object)) {
        if ($order -contains $key) { continue }
        if (-not $Map[$key]) { continue }
        $lines += "$key=$($Map[$key])"
    }
    return $lines
}

function Read-Secret([string]$Name) {
    # -AsSecureString echoes nothing, so the value never appears on screen, in the
    # console buffer, or in a screenshot of the window.
    $secure = Read-Host -AsSecureString "Paste $Name"
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

# --- What is already in .env --------------------------------------------------

$values = @{}
if (Test-Path -LiteralPath $EnvPath) {
    foreach ($line in Get-Content -LiteralPath $EnvPath) {
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            $values[$Matches[1]] = $Matches[2].Trim().Trim('"')
        }
    }
}
if (-not $values['SUPABASE_URL']) { $values['SUPABASE_URL'] = 'https://oknrivipgpptsebeyvsq.supabase.co' }
if (-not $values['APP_URL']) { $values['APP_URL'] = 'https://mtlledger.com' }

if ($RotateSecrets) { foreach ($key in $secretKeys) { $values.Remove($key) } }
$missing = @($secretKeys | Where-Object { -not $values[$_] })
if ($missing.Count -and -not $DryRun) {
    Say 'Secrets missing from .env. Input is hidden: nothing is echoed.'
    foreach ($key in $missing) { $values[$key] = Read-Secret $key }
}
if ($values['SYNC_CREDENTIAL_KEY']) {
    try { $bytes = [Convert]::FromBase64String($values['SYNC_CREDENTIAL_KEY']) }
    catch { throw 'SYNC_CREDENTIAL_KEY is not valid base64.' }
    if ($bytes.Length -ne 32) {
        throw "SYNC_CREDENTIAL_KEY decodes to $($bytes.Length) bytes, not 32 - it must be the exact value the web app uses."
    }
}

# The slots are named by this script, so MT5_FLEET_DIRS never has to be pasted by
# hand. reset-host.ps1 keeps existing slots and refuses to edit .env.
$values['MT5_FLEET_DIRS'] = ((1..$FleetSize | ForEach-Object { Join-Path $fleetRoot ('slot-{0:D2}' -f $_) }) -join ';')
$values['FLEET_SIZE'] = "$FleetSize"
$values['WATCH_SECONDS'] = '1'
$values['LOCK_POLL_SECONDS'] = '10'
$values['ENFORCE_LOCK'] = '1'
$values['BACKFILL_DAYS'] = "$BackfillDays"

# setup_vps.ps1 ends with a `--once` that validates MT5_PATH, so the file has to
# exist at that point; the copy reset-host builds later is what runs for real.
$copyPath = 'C:\MT5-Sync\terminal64.exe'
if (-not (Test-Path -LiteralPath (Join-Path $TerminalSource 'terminal64.exe'))) {
    $values['MT5_PATH'] = $copyPath
} else {
    $values['MT5_PATH'] = Join-Path $TerminalSource 'terminal64.exe'
}
$values['MT5_PORTABLE'] = '1'

Write-Host ''
Write-Host 'Install the sync host' -ForegroundColor Cyan
Write-Host ("  code     : {0}" -f $Source)
Write-Host ("  host     : {0}" -f $Root)
Write-Host ("  terminal : {0}" -f $TerminalSource)
Write-Host ("  slots    : {0} under {1}" -f $FleetSize, $fleetRoot)
Write-Host ("  history  : {0}-day first read, {1}-day re-arm" -f $BackfillDays, $DeepHistoryDays)
Write-Host ''
foreach ($key in (Format-Env $values)) {
    $name = ($key -split '=', 2)[0]
    if ($secretKeys -contains $name) {
        Write-Host ("  {0:<26} (set, hidden)" -f $name)
    } else {
        Write-Host ("  {0}" -f $key)
    }
}
Write-Host ''

if ($DryRun) {
    Write-Host 'DRY RUN: nothing is written, installed or deleted.' -ForegroundColor Yellow
    return
}

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this in an elevated PowerShell (Run as Administrator).'
}

# --- 1. .env ------------------------------------------------------------------

New-Item -ItemType Directory -Force -Path $Root | Out-Null
Set-Content -Path $EnvPath -Value (Format-Env $values) -Encoding ASCII
Say "wrote $EnvPath"

# --- 2. Python, the terminal, the package ------------------------------------

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Source 'setup_vps.ps1')
if ($LASTEXITCODE -ne 0) { throw "setup_vps.ps1 failed with exit code $LASTEXITCODE." }
if (-not (Test-Path -LiteralPath (Join-Path $TerminalSource 'terminal64.exe'))) {
    throw "No terminal64.exe at $TerminalSource after setup. Open MetaTrader 5 once to finish its wizard, then run this again."
}

# --- 3. Fleet slots -----------------------------------------------------------

$fleetScript = Join-Path $Source 'setup_fleet.ps1'
if ($FleetSize -gt 0 -and (Test-Path -LiteralPath $fleetScript)) {
    Say "preparing $FleetSize fleet slot(s)"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fleetScript `
        -Count $FleetSize -Root $fleetRoot -Source $TerminalSource
    if ($LASTEXITCODE -ne 0) { throw "setup_fleet.ps1 failed with exit code $LASTEXITCODE." }
}

# Now point at the copy reset-host.ps1 is about to make, not the source install.
$values['MT5_PATH'] = $copyPath
Set-Content -Path $EnvPath -Value (Format-Env $values) -Encoding ASCII
Say 'pointed MT5_PATH at the terminal copy'

# --- 4. Rebuild ---------------------------------------------------------------

if ($SkipRebuild) {
    Say 'stopping before the rebuild (-SkipRebuild)'
    Write-Host ("Next: powershell -File {0} -DeepHistoryDays {1} -Yes" -f (Join-Path $PSScriptRoot 'reset-host.ps1'), $DeepHistoryDays)
    return
}

Say 'rebuilding the host (the .env above is staged and restored byte-for-byte)'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'reset-host.ps1') `
    -Root $Root -Source $Source -TerminalSource $TerminalSource `
    -DeepHistoryDays $DeepHistoryDays -Yes
if ($LASTEXITCODE -ne 0) { throw "reset-host.ps1 failed with exit code $LASTEXITCODE." }

# --- 5. Start it --------------------------------------------------------------

Start-ScheduledTask -TaskName 'MTL Ledger Sync Supervisor' -ErrorAction SilentlyContinue
Start-Sleep -Seconds 15
$log = Join-Path $Root 'logs\supervisor.log'
if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 20 }

Write-Host ''
Write-Host 'Host installed.' -ForegroundColor Green
Write-Host ("  connect an account in the app, then: Get-Content {0} -Tail 40" -f $log)
