# Teacher-operated, completely offline application dependency setup.
# It never installs PostgreSQL, changes existing database tables/accounts,
# downloads files, or imports another Windows user's DPAPI credentials.
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [string]$PythonPath = ''
)

$ErrorActionPreference = 'Stop'
$folder = $PSScriptRoot
$dbFolder = Join-Path $folder 'database'
$pythonVenv = Join-Path $dbFolder '.venv\Scripts\python.exe'
$offlineDir = Join-Path $folder 'offline'
$wheels = Join-Path $offlineDir 'wheels'
$modelSource = Join-Path $offlineDir 'models\yolo26n-pose.pt'
$modelDestination = Join-Path (Join-Path $env:APPDATA 'Godot\app_userdata\KilosGrammar') 'pose_models\yolo26n-pose.pt'
$marker = Join-Path $dbFolder '.venv\kilos-offline-manifest.sha256'
$manifest = Join-Path $offlineDir 'manifest.json'

# A fresh classroom deployment must be writable by the current school-user
# account: this setup intentionally creates database/.venv beside the EXE.
# Program Files is therefore NOT a supported default install destination.
if (-not $CheckOnly) {
    foreach ($protected in @(${env:ProgramFiles}, ${env:ProgramFiles(x86)})) {
        if (-not $protected) { continue }
        $prefix = [IO.Path]::GetFullPath($protected).TrimEnd('\','/') + '\'
        if ([IO.Path]::GetFullPath($folder).StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) {
            throw 'Program Files is not writable for per-user offline Python setup. Install under %LOCALAPPDATA%\Programs\KilosGrammar instead.'
        }
    }
}

& (Join-Path $folder 'Test-OfflinePayload.ps1') -PayloadRoot $folder
if (-not (Test-Path -LiteralPath (Join-Path $folder 'KilosGrammar.exe') -PathType Leaf)) {
    throw 'KilosGrammar.exe missing. Copy the complete exported release folder before running setup.'
}
$pg = Join-Path ${env:ProgramFiles} 'PostgreSQL\18\bin\postgres.exe'
if (-not (Test-Path -LiteralPath $pg -PathType Leaf)) {
    $pgInstaller = Get-ChildItem -LiteralPath (Join-Path $offlineDir 'installers') -Filter 'postgresql-18*-windows-x64.exe' -File | Select-Object -First 1
    throw "Local PostgreSQL 18 x64 is missing. A teacher/administrator must use the supplied offline installer first (or select an approved existing PostgreSQL service): $($pgInstaller.FullName). No database installer has been run."
}
$pgService = Get-Service -Name 'postgresql-x64-18' -ErrorAction SilentlyContinue
if ($null -eq $pgService -or $pgService.Status -ne 'Running') {
    throw 'PostgreSQL 18 is installed but its standard service is not running. Ask the school administrator to inspect/start it before setup.'
}

$candidates = @()
if ($PythonPath) {
    $candidates += @{ exe=$PythonPath; args=@() }
} else {
    $py = Get-Command py.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $py) { $candidates += @{ exe=$py.Source; args=@('-3.11') } }
    $candidates += @{ exe=(Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe'); args=@() }
    $candidates += @{ exe=(Join-Path ${env:ProgramFiles} 'Python311\python.exe'); args=@() }
}
$chosen = $null
foreach ($candidate in $candidates) {
    if (-not (Test-Path -LiteralPath $candidate.exe -PathType Leaf)) { continue }
    try {
        $args = @($candidate.args) + @('-c', 'import sys,venv,ensurepip; sys.exit(0 if sys.version_info[:2]==(3,11) and sys.maxsize>2**32 else 1)')
        & $candidate.exe @args 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $chosen = $candidate; break }
    } catch { }
}
if ($null -eq $chosen) {
    $installer = Get-ChildItem -LiteralPath (Join-Path $offlineDir 'installers') -Filter 'python-3.11*-amd64.exe' -File | Select-Object -First 1
    throw "64-bit CPython 3.11 with venv/ensurepip is missing. Install it interactively from the staged offline installer: $($installer.FullName), then rerun Setup Offline.cmd. This script has not executed an installer."
}
$expectedHash = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
$installed = (Test-Path -LiteralPath $pythonVenv -PathType Leaf) -and (Test-Path -LiteralPath $marker -PathType Leaf) -and
    ((Get-Content -LiteralPath $marker -Raw).Trim() -eq $expectedHash)
if ($CheckOnly) {
    Write-Host ("Offline prerequisites valid; PostgreSQL service running; Python: {0}; virtual environment installed: {1}" -f $chosen.exe,$installed)
    if (-not $installed) { throw 'Target local Python dependencies have not been installed; run Setup Offline.cmd (without -CheckOnly).' }
    if (-not (Test-Path -LiteralPath $modelDestination -PathType Leaf)) { throw 'Target local pose model is missing; run Setup Offline.cmd.' }
    if ((Get-FileHash $modelDestination -Algorithm SHA256).Hash -ne (Get-FileHash $modelSource -Algorithm SHA256).Hash) {
        throw 'Installed pose model SHA256 differs from the release model.'
    }
    return
}
if ((Test-Path -LiteralPath $pythonVenv -PathType Leaf) -and -not $installed) {
    throw 'An existing, unrecognized Python virtual environment was found at database/.venv. Preserve it; ask a technician to inspect before replacing.'
}
if (-not $installed) {
    Write-Host 'Creating application-local Python 3.11 virtual environment. No Internet access will be used.'
    $venvArgs = @($chosen.args) + @('-m', 'venv', (Join-Path $dbFolder '.venv'))
    & $chosen.exe @venvArgs
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $pythonVenv)) { throw 'Local virtual environment creation failed.' }
    & $pythonVenv -c 'import sys; sys.exit(0 if sys.prefix!=sys.base_prefix and sys.version_info[:2]==(3,11) and sys.maxsize>2**32 else 1)'
    if ($LASTEXITCODE -ne 0) { throw 'Refusing package install outside expected 64-bit Python 3.11 virtual environment.' }
    $env:PIP_NO_INDEX = '1'
    $env:PIP_DISABLE_PIP_VERSION_CHECK = '1'
    try {
        & $pythonVenv -m pip --isolated install --no-index --no-cache-dir --only-binary ':all:' --find-links $wheels -r (Join-Path $folder 'requirements-offline.txt')
        if ($LASTEXITCODE -ne 0) { throw 'Offline wheels incomplete/incompatible. No online fallback is permitted.' }
        & $pythonVenv -c 'import psycopg,cv2,torch,ultralytics,lap; print("PASS local Python dependencies")'
        if ($LASTEXITCODE -ne 0) { throw 'Installed dependencies failed Python import validation.' }
    } finally {
        Remove-Item Env:PIP_NO_INDEX -ErrorAction SilentlyContinue
        Remove-Item Env:PIP_DISABLE_PIP_VERSION_CHECK -ErrorAction SilentlyContinue
    }
    Set-Content -LiteralPath $marker -Value $expectedHash -Encoding Ascii
}
if (Test-Path -LiteralPath $modelDestination -PathType Leaf) {
    if ((Get-FileHash $modelDestination -Algorithm SHA256).Hash -ne (Get-FileHash $modelSource -Algorithm SHA256).Hash) {
        throw 'Existing model differs from the release; preserve it and ask the teacher to review it manually.'
    }
} else {
    New-Item -ItemType Directory -Path (Split-Path -Parent $modelDestination) -Force | Out-Null
    Copy-Item -LiteralPath $modelSource -Destination $modelDestination
}
Write-Host 'Offline Python and YOLO prerequisites ready. Launch Play KilosGrammar.cmd.'
Write-Host 'The game launches the one-time database setup wizard if DPAPI credentials/schema are not yet configured.'
