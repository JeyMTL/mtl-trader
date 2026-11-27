# Prepare the terminal directories a fleet slot needs.
#
# A MetaTrader terminal runs from one directory, so N concurrent accounts need N
# directories - copies, not extra windows on one install. This copies a clean
# terminal into each slot, strips anything that could log the copy into the
# trader's own account, and gives it an empty profile so it opens with no chart
# and therefore downloads no market history.
#
#   powershell -ExecutionPolicy Bypass -File supervisor/setup_fleet.ps1 -Count 30
#
# Copy the printed MT5_FLEET_DIRS line into supervisor/.env and set FLEET_SIZE to
# the same count. Copies are ~400 MB each; 30 slots is about 12 GB.

param(
    [int]$Count = 4,
    [string]$Source = "C:\Program Files\MetaTrader 5",
    [string]$Root = "C:\MT5-Fleet",
    [string]$Profile = "SyncOnly",
    # A config\servers.dat that already knows the brokers you serve. A fresh
    # install only knows MetaQuotes' own servers, so `login:` for an Exness or
    # prop-firm account fails before it ever reaches the network. Point this at
    # the data folder of a terminal that has logged into those brokers, e.g.
    # %APPDATA%\MetaQuotes\Terminal\<id>\config\servers.dat
    [string]$ServersFrom = "",
    # Terminal builds from 6230 on (confirmed on 6230 and 6333) refuse the Python
    # IPC handshake until the terminal has authenticated once: a never-logged-in
    # install answers every initialize() with (-10005, 'IPC timeout') while the
    # journal shows "MCP started on 127.0.0.1:22346" and no login attempt. Copying
    # the source's account file is what carries that authenticated state into a
    # slot, so it is kept by default; -StripAccount restores the old wipe.
    [switch]$StripAccount
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path (Join-Path $Source "terminal64.exe"))) {
    throw "No terminal64.exe in '$Source'. Pass -Source with a real MT5 install."
}
if ($Count -lt 1) { throw "-Count must be at least 1." }

$running = Get-Process terminal64 -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($Source, "OrdinalIgnoreCase") }
if ($running) {
    throw "A terminal from '$Source' is running. Close it before copying: a running install copies as a half-written directory."
}

New-Item -ItemType Directory -Force -Path $Root | Out-Null
$dirs = @()

for ($slot = 1; $slot -le $Count; $slot++) {
    $dest = Join-Path $Root ("slot-{0:D2}" -f $slot)
    $dirs += $dest

    if (Test-Path (Join-Path $dest "terminal64.exe")) {
        Write-Host ("slot {0}: already present, keeping it" -f $slot)
        continue
    }

    Write-Host ("slot {0}: copying {1} -> {2}" -f $slot, $Source, $dest)
    $null = robocopy $Source $dest /E /NFL /NDL /NJH /NJS /NC /NS /R:1 /W:1
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy failed for slot $slot with exit code $LASTEXITCODE"
    }

    # A copy of a terminal that has been used carries that account with it: the
    # login, the server list, the sealed passwords and the downloaded history.
    # Every slot would then start on the trader's account before the supervisor
    # ever logs in, and two slots would fight over one session. That is why
    # `bases` and `logs` go: they are history, and a slot re-downloads what it
    # needs. `config\accounts.dat` is the one file kept, because a terminal that
    # has never logged in cannot be driven over IPC at all on current builds
    # (6230/6333) - the supervisor replaces the account with the slot's own on
    # its first initialize(), and refuses a terminal sitting on a different
    # account. Pass -StripAccount for the old behaviour if the source was never
    # logged in anyway.
    # servers.dat is deliberately kept: it is the list of broker servers, not
    # credentials. Deleting it leaves the slot unable to resolve any server name,
    # and the login fails with (-10001, 'IPC send failed') because the terminal
    # never gets as far as the network.
    $leftovers = @("bases", "profiles", "logs", "tester")
    if ($StripAccount) { $leftovers += "config\accounts.dat" }
    foreach ($leftover in $leftovers) {
        $path = Join-Path $dest $leftover
        if (Test-Path $path) { Remove-Item $path -Recurse -Force }
    }

    if ($ServersFrom) {
        $servers = if (Test-Path $ServersFrom -PathType Leaf) { $ServersFrom } else { Join-Path $ServersFrom "config\servers.dat" }
        if (-not (Test-Path $servers)) { throw "-ServersFrom did not find a servers.dat at '$ServersFrom'" }
        Copy-Item $servers (Join-Path $dest "config\servers.dat") -Force
    }

    # Portable data lives in this directory, so nothing here touches %APPDATA%
    # and no slot can see another slot's accounts or history.
    New-Item -ItemType Directory -Force -Path (Join-Path $dest "profiles\$Profile") | Out-Null

    # `[Experts]` is the Algo Trading pair. A terminal that has never had it set
    # is read-only to a program: the daily stop and the guard EA cannot cancel
    # or close anything, and nothing in the journal says why.
    $config = @"
[Common]
ProfileLast=$Profile
NewsEnable=0
[Experts]
AllowLiveTrading=1
Enabled=1
[Charts]
MaxBars=5000
SaveDeleted=0
"@
    $iniPath = Join-Path $dest "config\common.ini"
    New-Item -ItemType Directory -Force -Path (Split-Path $iniPath) | Out-Null
    # MT5 reads its ini files as UTF-16 with a BOM; a UTF-8 file is ignored.
    [System.IO.File]::WriteAllText($iniPath, $config, [System.Text.Encoding]::Unicode)

    $chartless = Join-Path $dest "profiles\$Profile"
    if (@(Get-ChildItem $chartless -Force).Count -gt 0) {
        throw "profile '$Profile' in $dest is not empty; a chart there would download market history"
    }
}

$joined = ($dirs -join ";")
Write-Host ""
Write-Host "Prepared $Count terminal(s) under $Root."
if ($StripAccount) {
    Write-Host "Account files were stripped: every slot starts logged out."
} else {
    Write-Host "config\accounts.dat is kept from the source: a slot can only be driven"
    Write-Host "over IPC once its terminal has authenticated at least once."
}
Write-Host "Each one starts with an empty profile and no chart, so a logged-in"
Write-Host "terminal stays near 140 MB instead of downloading chart history."
Write-Host ""
Write-Host "Add to supervisor/.env:"
Write-Host ("  FLEET_SIZE={0}" -f $Count)
Write-Host ("  MT5_FLEET_DIRS={0}" -f $joined)
Write-Host ""
Write-Host "The supervisor passes /portable itself; do not open these terminals by"
Write-Host "hand, or they will use %APPDATA% and a visible window."
