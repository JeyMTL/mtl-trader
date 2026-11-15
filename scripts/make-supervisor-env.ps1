# Builds supervisor/.env from the web app's .env.local.
#
# Run from anywhere:
#   powershell -ExecutionPolicy Bypass -File scripts/make-supervisor-env.ps1
#
# Values are copied, never printed. If a required key is missing from
# .env.local, the script names it and exits without writing a partial file.

$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$source = Join-Path $root '.env.local'
$target = Join-Path $root 'supervisor\.env'

if (-Not (Test-Path $source)) {
    Write-Host "No .env.local at $source" -ForegroundColor Red
    exit 1
}

$values = @{}
foreach ($line in Get-Content $source) {
    if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
    $name, $value = $line -split '=', 2
    $name = $name.Trim()
    $value = $value.Trim()
    if ($value.Length -ge 2) {
        $first = $value.Substring(0, 1)
        $last = $value.Substring($value.Length - 1, 1)
        if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
            $value = $value.Substring(1, $value.Length - 2)
        }
    }
    if ($name) { $values[$name] = $value }
}

$map = [ordered]@{
    'SUPABASE_URL'              = 'NEXT_PUBLIC_SUPABASE_URL'
    'SUPABASE_SERVICE_ROLE_KEY' = 'SUPABASE_SERVICE_ROLE_KEY'
    'SYNC_CREDENTIAL_KEY'       = 'SYNC_CREDENTIAL_KEY'
    'SYNC_SUPERVISOR_TOKEN'     = 'SYNC_SUPERVISOR_TOKEN'
}

$missing = @()
foreach ($entry in $map.GetEnumerator()) {
    if (-Not $values[$entry.Value]) { $missing += $entry.Value }
}
if ($missing.Count -gt 0) {
    Write-Host "Missing or empty in .env.local:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
    Write-Host "Generate the two sync values with:" -ForegroundColor Yellow
    Write-Host '  node -e "console.log(require(''crypto'').randomBytes(32).toString(''base64''))"   # SYNC_CREDENTIAL_KEY'
    Write-Host '  node -e "console.log(require(''crypto'').randomBytes(32).toString(''hex''))"     # SYNC_SUPERVISOR_TOKEN'
    Write-Host "Add them to .env.local, restart the server, then run this again."
    exit 1
}

$lines = @(
    '# Generated from .env.local by scripts/make-supervisor-env.ps1. Gitignored.'
    "SUPABASE_URL=$($values['NEXT_PUBLIC_SUPABASE_URL'])"
    "SUPABASE_SERVICE_ROLE_KEY=$($values['SUPABASE_SERVICE_ROLE_KEY'])"
    "SYNC_CREDENTIAL_KEY=$($values['SYNC_CREDENTIAL_KEY'])"
    "SYNC_SUPERVISOR_TOKEN=$($values['SYNC_SUPERVISOR_TOKEN'])"
    'APP_URL=http://127.0.0.1:3000'
)

# UTF-8 without a BOM: python-dotenv would read a BOM as part of the first key.
[System.IO.File]::WriteAllLines($target, $lines, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Wrote supervisor/.env" -ForegroundColor Green
Write-Host "No values were printed. Run: python supervisor/mt5_supervisor.py --once"
