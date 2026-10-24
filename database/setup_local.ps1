# Run manually from PowerShell: .\database\setup_local.ps1
# Optionally choose an interpreter: -PythonPath 'C:\Espressif\tools\python\python.exe'
# Verify interpreter discovery without installing: -CheckPythonOnly
# Installs the required Python driver into a private virtual environment.
# Does not create, migrate, or connect to a database.
param(
    [string]$PythonPath = '',
    [switch]$CheckPythonOnly
)

$ErrorActionPreference = 'Stop'
$virtualPython = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'

# Prefer a caller-selected interpreter, then search installed commands and the
# known Espressif Python location. `py` is optional, and Store app aliases may
# be nonfunctional; validate candidates before making any filesystem changes.
$candidates = @()
if (-not [string]::IsNullOrWhiteSpace($PythonPath)) {
    $candidates += @{ Exe = $PythonPath; Prefix = @() }
} else {
    foreach ($commandName in @('py', 'python', 'python3')) {
        $command = Get-Command -Name $commandName -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $command) {
            $prefix = @()
            if ($commandName -eq 'py') { $prefix = @('-3') }
            $candidates += @{ Exe = $command.Source; Prefix = $prefix }
        }
    }
    $espressifPython = 'C:\Espressif\tools\python\python.exe'
    if (Test-Path -LiteralPath $espressifPython -PathType Leaf) {
        $candidates += @{ Exe = $espressifPython; Prefix = @() }
    }
}

$chosen = $null
foreach ($candidate in $candidates) {
    try {
        $argsForCheck = @($candidate.Prefix) + @('-c', 'import sys, venv, ensurepip; sys.exit(0 if sys.version_info >= (3, 11) else 1)')
        & $candidate.Exe @argsForCheck 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $chosen = $candidate
            break
        }
    } catch {
        # Invalid/missing interpreter or Windows Store alias. Try next one.
    }
}

if ($null -eq $chosen -and (
    (-not [string]::IsNullOrWhiteSpace($PythonPath)) -or
    (-not (Test-Path -LiteralPath $virtualPython -PathType Leaf))
)) {
    throw 'No compatible Python 3.11+ with venv/ensurepip was found. Use -PythonPath with a valid local python.exe.'
}
if ($CheckPythonOnly) {
    if ($null -ne $chosen) {
        Write-Host "Compatible Python: $($chosen.Exe)"
    } else {
        Write-Host "Existing virtual environment: $virtualPython"
    }
    return
}

if (-not (Test-Path -LiteralPath $virtualPython -PathType Leaf)) {
    $argsForVenv = @($chosen.Prefix) + @('-m', 'venv', (Join-Path $PSScriptRoot '.venv'))
    # Windows PowerShell 5.1 can treat nonfatal stderr from native tools as
    # terminating when ErrorActionPreference is Stop. Judge by process exit.
    $originalPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $chosen.Exe @argsForVenv
        $venvExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $originalPreference
    }
    if ($venvExitCode -ne 0 -or (-not (Test-Path -LiteralPath $virtualPython -PathType Leaf))) {
        throw 'Could not create the local Python virtual environment. Try -PythonPath with a different Python installation.'
    }
}

# Refuse to install into a global Python if the venv path resolves unexpectedly.
& $virtualPython -c 'import sys; sys.exit(0 if sys.prefix != sys.base_prefix else 1)'
if ($LASTEXITCODE -ne 0) { throw 'Refusing package install: Python is not in a virtual environment.' }
$originalPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    & $virtualPython -m pip install -r (Join-Path $PSScriptRoot 'requirements.txt')
    $pipExitCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $originalPreference
}
if ($pipExitCode -ne 0) { throw 'Could not install the PostgreSQL Python driver.' }
Write-Host 'Python driver installed. Review database/README.md before running database/run_local.ps1.'
