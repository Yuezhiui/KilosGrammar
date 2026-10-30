# Teacher-operated, completely offline application dependency setup.
# It never installs PostgreSQL, changes existing database tables/accounts,
# downloads files, or imports another Windows user's DPAPI credentials.
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$PythonOnly,
    [switch]$AutoInstallPython,
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
if ($CheckOnly -and $AutoInstallPython) {
    throw 'CheckOnly must never install Python.'
}

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
if (-not $PythonOnly) {
    $pgService = Get-Service -Name 'postgresql-x64-18' -ErrorAction SilentlyContinue
    if ($null -eq $pgService) {
        $pgInstaller = Get-ChildItem -LiteralPath (Join-Path $offlineDir 'installers') -Filter 'postgresql-18*-windows-x64.exe' -File | Select-Object -First 1
        throw "Local PostgreSQL 18 service is missing. Ask a school administrator to install and configure the bundled offline PostgreSQL installer: $($pgInstaller.FullName). No PostgreSQL installer has been run."
    }
    if ($pgService.Status -ne 'Running') {
        if ($CheckOnly) {
            throw 'PostgreSQL 18 is installed but stopped. Start the approved postgresql-x64-18 service before checking setup.'
        }
        # Only a previously installed standard service may be started, without
        # elevation. Never install, repair, reconfigure or reset PostgreSQL.
        try {
            Start-Service -Name 'postgresql-x64-18' -ErrorAction Stop
            $pgService.WaitForStatus('Running', [TimeSpan]::FromSeconds(8))
        } catch {
            throw 'PostgreSQL 18 is installed but cannot be started with this Windows account. Ask the school administrator to start the existing postgresql-x64-18 service; student records and database configuration were not modified.'
        }
    }
}

$candidates = @()
if ($PythonPath) {
    $candidates += @{ exe=$PythonPath; args=@() }
} else {
    $py = Get-Command py.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $py) { $candidates += @{ exe=$py.Source; args=@('-3.11') } }
    $candidates += @{ exe=(Join-Path $env:LOCALAPPDATA 'Programs\KilosGrammar-Python311\python.exe'); args=@() }
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
    if (-not $AutoInstallPython) {
        throw "64-bit CPython 3.11 with venv/ensurepip is missing. Use the bundled offline installer: $($installer.FullName), then rerun Setup Offline.cmd. No installer has been run."
    }
    if ($null -eq $installer) { throw 'Bundled CPython 3.11 x64 installer is missing.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $installer.FullName
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch 'O=Python Software Foundation') {
        throw 'Bundled Python installer signature is not a valid Python Software Foundation signature; refusing automatic installation.'
    }
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA must be present for per-user Python installation.' }
    $target = Join-Path $env:LOCALAPPDATA 'Programs\KilosGrammar-Python311'
    $targetPython = Join-Path $target 'python.exe'
    if (Test-Path -LiteralPath $target) {
        throw "An existing or incomplete Python installation at $target must be inspected by a technician; refusing overwrite."
    }
    Write-Host 'Installing the SHA256-verified, officially signed bundled Python 3.11 under the current Windows account (no Internet or administrator privileges).'
    # Test-OfflinePayload checked SHA256 before this installer may run. Isolate
    # its TargetDir from the application, system Python and existing installs.
    $arguments = @('/quiet', 'InstallAllUsers=0', 'Include_launcher=0',
        'Include_pip=1', 'Include_venv=1', 'Include_test=0',
        ('TargetDir="' + $target + '"'))
    $installProcess = Start-Process -FilePath $installer.FullName -ArgumentList $arguments -Wait -PassThru -ErrorAction Stop
    if ($installProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $targetPython -PathType Leaf)) {
        throw "Bundled Python per-user install did not complete (exit code $($installProcess.ExitCode)). Existing files were preserved; do not rerun until the destination is inspected."
    }
    & $targetPython -c 'import sys,venv,ensurepip; sys.exit(0 if sys.version_info[:2]==(3,11) and sys.maxsize>2**32 else 1)'
    if ($LASTEXITCODE -ne 0) { throw 'Per-user Python failed Python 3.11 x64 validation.' }
    $chosen = @{ exe=$targetPython; args=@() }
}
$expectedHash = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
$installed = (Test-Path -LiteralPath $pythonVenv -PathType Leaf) -and (Test-Path -LiteralPath $marker -PathType Leaf) -and
    ((Get-Content -LiteralPath $marker -Raw).Trim() -eq $expectedHash)
if ($CheckOnly) {
    Write-Host ("Offline prerequisites valid; Python: {0}; virtual environment installed: {1}" -f $chosen.exe,$installed)
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
Write-Host 'Offline Python and YOLO prerequisites ready (no download).'
if (-not $PythonOnly) {
    Write-Host 'PostgreSQL 18 service running. Launch Play KilosGrammar.cmd.'
    Write-Host 'The game offers its existing database wizard if DPAPI credentials/schema are not yet configured.'
}
