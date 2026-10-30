# Supported offline launch entrypoint for the installed game. First launch may
# bootstrap ONLY the current user's verified Python/YOLO runtime. Existing
# PostgreSQL services may be started; new PostgreSQL install, role and schema
# creation always require teacher/administrator review and confirmation.
[CmdletBinding()]
param([switch]$CheckOnly)

$ErrorActionPreference = 'Stop'
$game = Join-Path $PSScriptRoot 'KilosGrammar.exe'
$pck = Join-Path $PSScriptRoot 'KilosGrammar.pck'
$python = Join-Path $PSScriptRoot 'database\.venv\Scripts\python.exe'
$setupMarker = Join-Path $PSScriptRoot 'database\.venv\kilos-offline-manifest.sha256'
$offlineManifest = Join-Path $PSScriptRoot 'offline\manifest.json'
$modelSource = Join-Path $PSScriptRoot 'offline\models\yolo26n-pose.pt'
$modelDestination = Join-Path (Join-Path $env:APPDATA 'Godot\app_userdata\KilosGrammar') 'pose_models\yolo26n-pose.pt'
if ($CheckOnly) {
    & (Join-Path $PSScriptRoot 'Test-LaunchPreflight.ps1') -PackageRoot $PSScriptRoot -RequireOfflineRuntime
    return
}
foreach ($required in @($game, $pck, $offlineManifest, $modelSource)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Incomplete game installation: $required. Reinstall the complete verified offline package."
    }
}
$expectedMarker = (Get-FileHash -LiteralPath $offlineManifest -Algorithm SHA256).Hash
$ready = (Test-Path -LiteralPath $python -PathType Leaf) -and
    (Test-Path -LiteralPath $setupMarker -PathType Leaf) -and
    (Test-Path -LiteralPath $modelDestination -PathType Leaf)
if ($ready) {
    $ready = ((Get-Content -LiteralPath $setupMarker -Raw).Trim() -eq $expectedMarker) -and
        ((Get-FileHash -LiteralPath $modelDestination -Algorithm SHA256).Hash -eq
         (Get-FileHash -LiteralPath $modelSource -Algorithm SHA256).Hash)
}
if (-not $ready) {
    Write-Host 'Preparing your offline Python and camera dependencies. No Internet or PostgreSQL database changes.'
    & (Join-Path $PSScriptRoot 'Install-OnSchoolPC.ps1') -PythonOnly -AutoInstallPython
    if (-not (Test-Path -LiteralPath $python -PathType Leaf) -or
        -not (Test-Path -LiteralPath $setupMarker -PathType Leaf)) {
        throw 'Offline runtime setup did not complete. Run Setup Offline.cmd to see the setup instructions.'
    }
}
# Existing Windows services only: never start the PostgreSQL installer or
# elevate silently. This service must already have been configured by an admin.
$postgres = Get-Service -Name 'postgresql-x64-18' -ErrorAction SilentlyContinue
if ($null -eq $postgres) {
    $installer = Get-ChildItem (Join-Path $PSScriptRoot 'offline\installers') -Filter 'postgresql-18*-windows-x64.exe' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    throw "PostgreSQL 18 is not installed/configured. Ask your administrator to install it from $($installer.FullName), then run Setup Offline.cmd. The launcher never installs PostgreSQL or resets any data."
}
if ($postgres.Status -ne 'Running') {
    Write-Host 'Starting the already-installed PostgreSQL 18 service...'
    try {
        Start-Service -Name 'postgresql-x64-18' -ErrorAction Stop
        $postgres.WaitForStatus('Running', [TimeSpan]::FromSeconds(8))
    } catch {
        throw 'Cannot start the existing PostgreSQL 18 service with this Windows account. Ask the school administrator to start postgresql-x64-18; no database configuration or records were changed.'
    }
}
$credentials = Join-Path $env:LOCALAPPDATA 'KilosGrammar\db_credentials.xml'
if (Test-Path -LiteralPath $credentials -PathType Leaf) {
    # start_auto checks its own /health and starts only the app's localhost API
    # if it is not already healthy. It never creates/changes database objects.
    & (Join-Path $PSScriptRoot 'database\start_auto.ps1')
    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'Local API is not yet ready. The game can show its existing private database setup/repair wizard.'
    }
} else {
    Write-Host 'First launch: use the game database setup wizard to connect an approved PostgreSQL database. Creation/migration require explicit approval.'
}
$previousPython = $env:KILOSGRAMMAR_PYTHON
$env:KILOSGRAMMAR_PYTHON = $python
try {
    Start-Process -FilePath $game -WorkingDirectory $PSScriptRoot | Out-Null
} finally {
    if ($null -eq $previousPython) {
        Remove-Item Env:KILOSGRAMMAR_PYTHON -ErrorAction SilentlyContinue
    } else {
        $env:KILOSGRAMMAR_PYTHON = $previousPython
    }
}
