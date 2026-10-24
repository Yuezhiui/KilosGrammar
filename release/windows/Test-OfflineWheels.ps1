# Resolve every dependency from the staged wheelhouse, with network blocked.
# Modern pip's --dry-run/--ignore-installed leaves this PC untouched.
[CmdletBinding()]
param([string]$PythonExe = '')

$ErrorActionPreference = 'Stop'
$requirements = Join-Path $PSScriptRoot 'requirements-offline.txt'
$wheelhouse = Join-Path $PSScriptRoot 'offline\wheels'
if (-not (Test-Path -LiteralPath $wheelhouse -PathType Container)) { throw 'Missing offline wheelhouse.' }
$commandPath = $PythonExe
$prefix = @()
if (-not $commandPath) {
    $py = Get-Command 'py.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $py) { $commandPath=$py.Source; $prefix=@('-3.11') }
}
if (-not $commandPath -or -not (Test-Path -LiteralPath $commandPath -PathType Leaf)) {
    throw 'Build preflight needs CPython 3.11 x64 to resolve the offline wheelhouse. Supply -PythonExe with a valid Python 3.11 executable.'
}
& $commandPath @prefix -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3,11) and sys.maxsize > 2**32 else 1)'
if ($LASTEXITCODE -ne 0) { throw 'Wheel preflight requires CPython 3.11 x64.' }
$env:PIP_NO_INDEX = '1'
$env:PIP_DISABLE_PIP_VERSION_CHECK = '1'
try {
    & $commandPath @prefix -m pip --isolated install --dry-run --ignore-installed --no-index --no-cache-dir --only-binary ':all:' --find-links $wheelhouse -r $requirements
    if ($LASTEXITCODE -ne 0) { throw 'Offline wheel resolver failed: missing/incompatible transitive wheels. No download/install was attempted.' }
} finally {
    Remove-Item Env:PIP_NO_INDEX -ErrorAction SilentlyContinue
    Remove-Item Env:PIP_DISABLE_PIP_VERSION_CHECK -ErrorAction SilentlyContinue
}
Write-Host 'PASS offline wheel dependency closure (dry run, no installation or network).'
