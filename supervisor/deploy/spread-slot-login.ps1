# Copy one slot's authenticated account file to every other fleet slot.
#
# A portable folder that has never authenticated boots MT5's "open an account"
# wizard, and that wizard owns the folder's IPC pipe: every program login then
# answers `-10005 IPC timeout`. MT5 accepts that first login only from a person,
# so the runbook asks for one hand login. Doing it in one slot and copying the
# file it wrote is the same login for the rest of the fleet, without thirteen
# more of them.
#
#   powershell -ExecutionPolicy Bypass -File spread-slot-login.ps1 -Source C:\MT5-Fleet\slot-01
#
# The fleet must be stopped: MT5 writes accounts.dat when it exits, so copying
# under a live terminal either misses the login or corrupts the file.

param(
    [Parameter(Mandatory = $true)][string]$Source,
    [string]$FleetDir = 'C:\MT5-Fleet',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$sourceDir = (Resolve-Path -LiteralPath $Source).Path
$sourceFile = Join-Path $sourceDir 'config\accounts.dat'
if (-not (Test-Path -LiteralPath $sourceFile)) {
    throw "No account file at $sourceFile - log that slot in once by hand first."
}
if ((Get-Item -LiteralPath $sourceFile).Length -eq 0) {
    throw "$sourceFile is empty - that slot has not authenticated yet."
}

$slots = @(Get-ChildItem -Path $FleetDir -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'terminal64.exe') })
if ($slots.Count -eq 0) { throw "No slot folders under $FleetDir" }

$running = @(Get-Process terminal64 -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "$FleetDir\*" })
if ($running.Count -gt 0 -and -not $Force) {
    $ids = ($running | ForEach-Object { $_.Id }) -join ', '
    throw "$($running.Count) fleet terminal(s) are running ($ids). Stop the task and let them close, or pass -Force if you know the folders are idle."
}

# The source keeps the login it just made: its own seed must move on to it too,
# otherwise the first failed attempt there restores the older, unauthenticated
# file and the slot is back on the wizard.
Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $sourceDir 'config\accounts.dat.seed') -Force
"  {0}  (source, seed refreshed)" -f (Split-Path $sourceDir -Leaf)

$copied = 0
foreach ($slot in $slots) {
    if ($slot.FullName -eq $sourceDir) { continue }
    $config = Join-Path $slot.FullName 'config'
    $account = Join-Path $config 'accounts.dat'
    $seed = Join-Path $config 'accounts.dat.seed'
    Copy-Item -LiteralPath $sourceFile -Destination $account -Force
    # The seed is what a failed attempt restores, so it has to carry the login
    # as well or the very first failure puts the wizard back.
    Copy-Item -LiteralPath $sourceFile -Destination $seed -Force
    $copied++
    "  {0}  accounts.dat + seed ({1} bytes)" -f $slot.Name, (Get-Item -LiteralPath $account).Length
}

"copied the login from $(Split-Path $sourceDir -Leaf) to $copied slot(s)"
