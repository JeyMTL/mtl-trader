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
    # Never fatal. A supervisor left running by an earlier start still holds this
    # file open, and with $ErrorActionPreference = 'Stop' a failed append would
    # end the wrapper before it logged anything at all: the task then shows
    # LastTaskResult 1 and a log that has not changed since the older run.
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    try {
        $line | Out-File -FilePath $Log -Append -Encoding utf8
    } catch {
        [Console]::Error.WriteLine($line)
    }
}

function Clear-StraySupervisors {
    # A stopped task kills the powershell wrapper, not the python children it
    # started. Those keep their terminals, keep claiming accounts, and keep the
    # log open, so the next start looks like a silent failure. Clear the tree so
    # this wrapper really is the only supervisor on the host.
    $name = Split-Path $Script -Leaf
    $all = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
        Select-Object ProcessId, ParentProcessId, CommandLine)
    $selected = @($all | Where-Object { $_.CommandLine -and $_.CommandLine -like "*$name*" })
    if ($selected.Count -eq 0) { return }

    # Children are `python -c "...spawn_main..."` and do not carry the script
    # name, so add them by parentage, then their children.
    for ($round = 0; $round -lt 2; $round++) {
        $parents = @($selected | ForEach-Object { $_.ProcessId })
        $children = @($all | Where-Object { $parents -contains $_.ParentProcessId -and $parents -notcontains $_.ProcessId })
        if ($children.Count -eq 0) { break }
        $selected += $children
    }

    Write-Log "clearing $(@($selected).Count) supervisor process(es) left running from an earlier start: $(@($selected | ForEach-Object { $_.ProcessId }) -join ', ')"
    foreach ($item in $selected) {
        try { Stop-Process -Id $item.ProcessId -Force -ErrorAction Stop }
        catch { Write-Log "could not stop pid $($item.ProcessId): $($_.Exception.Message)" }
    }
    Start-Sleep -Seconds 2
}

if ($Once) {
    # -u: without it python block-buffers stdout into the log and a stalled
    # account leaves nothing to read.
    & $Python -u $Script --once 2>&1 | Tee-Object -FilePath $Log -Append
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

Clear-StraySupervisors

while ($true) {
    Rotate-Log
    Write-Log "starting $Script"
    try {
        & $Python -u $Script *>> $Log
        Write-Log "supervisor exited with code $LASTEXITCODE"
    } catch {
        Write-Log "supervisor crashed: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $RestartSeconds
}
