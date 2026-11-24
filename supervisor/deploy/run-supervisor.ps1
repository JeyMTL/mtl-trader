# Runs the sync supervisor forever, with a log file and a restart loop.
#
# The scheduled task starts this wrapper, not python directly, so a crash or an
# MT5 IPC failure produces a timestamped line in C:\MTLSync\logs\supervisor.log
# and a restart after RestartSeconds instead of a silently empty console.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\MTLSync\run-supervisor.ps1 -Once
#
# -Once runs a single `mt5_supervisor.py --once` and exits, which is what the
# verification step uses.

param(
    [string]$Python = 'C:\Program Files\Python312\python.exe',
    [string]$Script = 'C:\MTLSync\mt5_supervisor.py',
    [string]$LogDir = 'C:\MTLSync\logs',
    [int]$RestartSeconds = 15,
    [switch]$Once
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Python)) { throw "Python not found at $Python" }
if (-not (Test-Path $Script)) { throw "Supervisor not found at $Script" }

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log = Join-Path $LogDir 'supervisor.log'

function Write-Log([string]$Message) {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" |
        Out-File -FilePath $Log -Append -Encoding utf8
}

if ($Once) {
    & $Python $Script --once 2>&1 | Tee-Object -FilePath $Log -Append
    exit $LASTEXITCODE
}

# Keep one live log and three rotations. The supervisor prints a line per
# account per cycle, so an unattended month is a lot of text.
function Rotate-Log {
    if (-not (Test-Path $Log)) { return }
    if ((Get-Item $Log).Length -lt 10MB) { return }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Move-Item -Path $Log -Destination (Join-Path $LogDir "supervisor.$stamp.log") -Force
    Get-ChildItem -Path $LogDir -Filter 'supervisor.*.log' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip 3 |
        Remove-Item -Force
}

while ($true) {
    Rotate-Log
    Write-Log "starting $Script"
    try {
        & $Python $Script *>> $Log
        Write-Log "supervisor exited with code $LASTEXITCODE"
    } catch {
        Write-Log "supervisor crashed: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $RestartSeconds
}
