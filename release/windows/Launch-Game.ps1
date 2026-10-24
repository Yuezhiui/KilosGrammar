# Run from the extracted release folder. Uses the target-local Python venv
# and lets the existing Godot/PostgreSQL launcher perform normal health/retry.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$game = Join-Path $PSScriptRoot 'KilosGrammar.exe'
$python = Join-Path $PSScriptRoot 'database\.venv\Scripts\python.exe'
$setupMarker = Join-Path $PSScriptRoot 'database\.venv\kilos-offline-manifest.sha256'
if (-not (Test-Path -LiteralPath $game -PathType Leaf)) { throw 'Game EXE is missing from the release folder.' }
if (-not (Test-Path -LiteralPath $python -PathType Leaf) -or -not (Test-Path -LiteralPath $setupMarker -PathType Leaf)) {
    throw 'Offline Python setup is incomplete. Run Setup Offline.cmd on this computer before launching.'
}
$env:KILOSGRAMMAR_PYTHON = $python
try {
    Start-Process -FilePath $game -WorkingDirectory $PSScriptRoot | Out-Null
} finally {
    Remove-Item Env:KILOSGRAMMAR_PYTHON -ErrorAction SilentlyContinue
}
