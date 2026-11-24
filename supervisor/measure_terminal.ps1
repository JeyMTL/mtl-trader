<#
.SYNOPSIS
Measures how much RAM one MT5 terminal costs on this host.

.DESCRIPTION
Vendor guides quote wildly different numbers (100 MB to 1.5 GB per terminal)
because it depends on charts, history and whether the MQL5 community features
are on. Sizing a sync host from somebody else's average is how you buy 32 GB for
a workload that uses 400 MB, so measure the terminal you actually run:

  * a terminal that has just started reads low - history and tick caches fill in
    over the first hours, so a steady-state figure needs time on the clock;
  * a terminal that never logged in has no history at all, which makes its
    figure a floor, not a target.

Run it against the portable copy the supervisor uses so the number matches the
process you will actually be paying for.

.EXAMPLE
.\measure_terminal.ps1 -Seconds 120

.EXAMPLE
# Start the portable copy, measure it, then close it again.
.\measure_terminal.ps1 -TerminalPath C:\MT5-Sync\terminal64.exe -Seconds 300 -StopWhenDone
#>
[CmdletBinding()]
param(
    # terminal64.exe to measure. Defaults to MT5_PATH, else the newest install.
    [string]$TerminalPath,

    # How long to sample for.
    [int]$Seconds = 60,

    # Seconds between samples.
    [int]$IntervalSeconds = 5,

    # Close the terminal at the end, but only if this script started it.
    [switch]$StopWhenDone
)

$ErrorActionPreference = 'Stop'

function Get-Footprint {
    param([System.Diagnostics.Process]$Process)
    # PrivateMemorySize64 is the figure that matters for sizing a box: the
    # working set can be trimmed under pressure, the private commit cannot.
    [pscustomobject]@{
        WorkingSetMB = [math]::Round($Process.WorkingSet64 / 1MB)
        PrivateMB    = [math]::Round($Process.PrivateMemorySize64 / 1MB)
        Threads      = $Process.Threads.Count
        Handles      = $Process.HandleCount
    }
}

function Resolve-Terminal {
    param([string]$Path)

    if ($Path) {
        if (-not (Test-Path -LiteralPath $Path)) { throw "not found: $Path" }
        return (Resolve-Path -LiteralPath $Path).Path
    }

    $running = Get-Process terminal64 -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($running -and $running.Path) { return $running.Path }

    if ($env:MT5_PATH -and (Test-Path -LiteralPath $env:MT5_PATH)) {
        return $env:MT5_PATH
    }

    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    $found = foreach ($root in $roots) {
        Get-ChildItem -Path $root -Filter 'terminal64.exe' -Recurse -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    }
    $found = @($found) | Sort-Object LastWriteTime -Descending
    if (-not $found) {
        throw "no terminal64.exe found; pass -TerminalPath (e.g. C:\MT5-Sync\terminal64.exe)"
    }
    return $found[0].FullName
}

$exe = Resolve-Terminal -Path $TerminalPath
Write-Host "terminal : $exe"

$before = @(Get-Process terminal64 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
$process = Get-Process terminal64 -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $exe } |
    Sort-Object StartTime -Descending |
    Select-Object -First 1

$started = $false
if (-not $process) {
    Write-Host "starting : (not running)"
    Start-Process -FilePath $exe | Out-Null
    $started = $true
    $deadline = (Get-Date).AddSeconds(90)
    while (-not $process -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $process = Get-Process terminal64 -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $exe -and $before -notcontains $_.Id } |
            Sort-Object StartTime -Descending |
            Select-Object -First 1
    }
    if (-not $process) { throw "terminal did not start: $exe" }
} else {
    Write-Host ("already running since {0:HH:mm:ss}" -f $process.StartTime)
}

Write-Host ("sampling : {0}s, every {1}s (Ctrl+C to stop early)`n" -f $Seconds, $IntervalSeconds)

$samples = New-Object System.Collections.Generic.List[object]
$endAt = (Get-Date).AddSeconds($Seconds)
try {
    while ((Get-Date) -lt $endAt) {
        # The terminal can disappear mid-run (crash, live update); a measurement
        # must not fail just because the thing under test did.
        $process.Refresh()
        if ($process.HasExited) { Write-Warning "terminal exited during sampling"; break }
        $footprint = Get-Footprint -Process $process
        $samples.Add([pscustomobject]@{
            Time         = (Get-Date).ToString('HH:mm:ss')
            WorkingSetMB = $footprint.WorkingSetMB
            PrivateMB    = $footprint.PrivateMB
            Threads      = $footprint.Threads
            Handles      = $footprint.Handles
        })
        Start-Sleep -Seconds $IntervalSeconds
    }
}
finally {
    if ($started -and $StopWhenDone -and -not $process.HasExited) {
        Write-Host "`nstopping : (started by this script)"
        # Forced, not CloseMainWindow: MT5 can come back by itself after a
        # graceful close (a pending restart, a live update), which leaves a
        # terminal running that nothing is watching.
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        $left = Get-Process terminal64 -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $exe }
        if ($left) {
            Write-Warning ("terminal came back: still running as {0}" -f ($left.Id -join ', '))
        }
    }
}

if (-not $samples.Count) { throw "no samples collected" }

$samples | Format-Table -AutoSize

$workingSets = @($samples | Select-Object -ExpandProperty WorkingSetMB)
$privates = @($samples | Select-Object -ExpandProperty PrivateMB)
# The tail is the number to size from: the first samples are a terminal that has
# not finished downloading history yet.
$tail = @($privates | Select-Object -Last ([Math]::Max(1, [Math]::Ceiling($privates.Count / 3))))
$steady = [math]::Round(($tail | Measure-Object -Average).Average)

Write-Host ""
Write-Host ("samples  : {0} over {1}s" -f $samples.Count, $Seconds)
Write-Host ("working  : first {0} MB, peak {1} MB, last {2} MB" -f $workingSets[0], ($workingSets | Measure-Object -Maximum).Maximum, $workingSets[-1])
Write-Host ("private  : first {0} MB, peak {1} MB, steady {2} MB (last third)" -f $privates[0], ($privates | Measure-Object -Maximum).Maximum, $steady)
Write-Host ""
Write-Host "Sizing note: this is one process on this host for this long. Multiply the"
Write-Host "steady figure by the terminals you plan to run, add Windows itself, and"
Write-Host "leave headroom for the history that keeps growing after the sample ends."
Write-Host "A terminal with no account logged in is a floor, not a target."
