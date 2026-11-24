# Registers the supervisor to start at logon and restart if it dies.
#
# Run elevated, after C:\MTLSync\.env exists and `run-supervisor.ps1 -Once` has
# printed a clean run.
#
#   powershell -ExecutionPolicy Bypass -File C:\MTLSync\register-task.ps1
#
# The trigger is "at logon" rather than "at startup" on purpose: MT5 is a GUI
# terminal and the MetaTrader5 package talks to it over Windows IPC, which is
# reliable in an interactive session and not in session 0. The server therefore
# needs auto-logon (see docs/SUPERVISOR_VPS.md, step 6) so a reboot brings both
# the desktop session and this task back.

param(
    [string]$TaskName = 'MTL Ledger Sync Supervisor',
    [string]$Wrapper = 'C:\MTLSync\run-supervisor.ps1',
    [string]$Python = 'C:\Program Files\Python312\python.exe',
    [string]$RunAs = "$env:USERDOMAIN\$env:USERNAME"
)

$ErrorActionPreference = 'Stop'

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this in an elevated PowerShell (Run as Administrator).'
}

foreach ($path in @($Wrapper, $Python)) {
    if (-not (Test-Path $path)) { throw "Not found: $path" }
}

$argument = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Python "{1}"' -f $Wrapper, $Python
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument -WorkingDirectory 'C:\MTLSync'
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $RunAs

# ExecutionTimeLimit zero: this process is meant to run for weeks. The restart
# settings cover the case where python exits on its own; the wrapper's own loop
# covers the case where it is the wrapper that dies.
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew `
    -RestartCount 25 `
    -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -RunLevel Highest `
    -Force | Out-Null

Write-Host "Registered '$TaskName' to start at logon for $RunAs." -ForegroundColor Cyan
Write-Host 'Starting it now...' -ForegroundColor Cyan
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 5
Get-ScheduledTask -TaskName $TaskName | Select-Object TaskName, State
Write-Host 'Log: C:\MTLSync\logs\supervisor.log' -ForegroundColor Cyan
