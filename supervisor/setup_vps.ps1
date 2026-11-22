# MTL Ledger - one-shot setup for the hosted sync supervisor on a Windows VPS.
#
# Run as Administrator on the VPS, from a copy of the repo:
#   powershell -ExecutionPolicy Bypass -File C:\MTL\supervisor\setup_vps.ps1
#
# Installs Python 3.12, the MetaTrader 5 terminal, the supervisor dependencies,
# writes C:\MTLSync\.env and registers a logon task so it survives reboots.
# Prompts for the three secrets (they live in Vercel -> Settings -> Environment
# Variables); nothing is echoed or written anywhere except .env.

$ErrorActionPreference = 'Stop'

function Say($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this in an elevated PowerShell (Run as Administrator).'
}

$PythonDir = 'C:\Program Files\Python312'
$Python = Join-Path $PythonDir 'python.exe'
$Target = 'C:\MTLSync'
$Source = Join-Path $PSScriptRoot 'mt5_supervisor.py'

if (-not (Test-Path $Source)) {
    throw "mt5_supervisor.py not found next to this script ($Source). Copy the supervisor folder to the VPS first."
}

# 1. Python 3.12 -------------------------------------------------------------
if (-not (Test-Path $Python)) {
    Say 'Installing Python 3.12'
    $installer = Join-Path $env:TEMP 'python-3.12.7-amd64.exe'
    Invoke-WebRequest 'https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe' -OutFile $installer -UseBasicParsing
    Start-Process $installer -ArgumentList '/quiet', 'InstallAllUsers=1', 'PrependPath=1', 'Include_test=0' -Wait
}
& $Python --version

# 2. MetaTrader 5 terminal ---------------------------------------------------
$Terminal = 'C:\Program Files\MetaTrader 5\terminal64.exe'
if (-not (Test-Path $Terminal)) {
    Say 'Installing MetaTrader 5'
    $mt5 = Join-Path $env:TEMP 'mt5setup.exe'
    Invoke-WebRequest 'https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe' -OutFile $mt5 -UseBasicParsing
    Start-Process $mt5 -ArgumentList '/auto' -Wait
    Start-Sleep -Seconds 20
}
if (-not (Test-Path $Terminal)) { throw "MT5 terminal not found at $Terminal - open it once, finish the wizard, rerun." }

# 3. Supervisor + dependencies ----------------------------------------------
Say 'Installing supervisor into C:\MTLSync'
New-Item -ItemType Directory -Force -Path $Target | Out-Null
Copy-Item $Source (Join-Path $Target 'mt5_supervisor.py') -Force
Copy-Item (Join-Path $PSScriptRoot 'requirements.txt') $Target -Force
& $Python -m pip install --quiet --upgrade pip
& $Python -m pip install --quiet -r (Join-Path $Target 'requirements.txt')

# 4. Secrets ----------------------------------------------------------------
$EnvFile = Join-Path $Target '.env'
$SupabaseUrl = 'https://oknrivipgpptsebeyvsq.supabase.co'
if (Test-Path $EnvFile) {
    Say ".env already exists at $EnvFile - keeping it, skipping prompts"
} else {
    Say 'Paste the three values from Vercel -> Settings -> Environment Variables'
    $ServiceKey = Read-Host 'SUPABASE_SERVICE_ROLE_KEY'
    $CredKey = Read-Host 'SYNC_CREDENTIAL_KEY'
    $SupToken = Read-Host 'SYNC_SUPERVISOR_TOKEN'
    @(
        "SUPABASE_URL=$SupabaseUrl"
        "SUPABASE_SERVICE_ROLE_KEY=$ServiceKey"
        "SYNC_CREDENTIAL_KEY=$CredKey"
        "SYNC_SUPERVISOR_TOKEN=$SupToken"
        'APP_URL=https://mtlledger.com'
        "MT5_PATH=$Terminal"
    ) | Set-Content -Path $EnvFile -Encoding ASCII
    Say "Wrote $EnvFile"
}

# 5. Start at logon, restart on crash ---------------------------------------
Say 'Registering scheduled task'
$Action = New-ScheduledTaskAction -Execute $Python -Argument (Join-Path $Target 'mt5_supervisor.py') -WorkingDirectory $Target
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable
Register-ScheduledTask -TaskName 'MTL Ledger Sync Supervisor' -Action $Action -Trigger $Trigger -Settings $Settings -RunLevel Highest -Force | Out-Null

Say 'Done. Dry run:'
& $Python (Join-Path $Target 'mt5_supervisor.py') --once
