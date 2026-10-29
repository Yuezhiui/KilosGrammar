# Read-only launch simulation; NO webcam, API request, PostgreSQL connection or
# process launch. Never guesses which process owns an occupied loopback port.
[CmdletBinding()]
param([string]$PackageRoot=$PSScriptRoot,[switch]$RequireOfflineRuntime)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($PackageRoot)
foreach ($name in @('KilosGrammar.exe','KilosGrammar.pck')) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $name) -PathType Leaf)) {
        throw "Would fail launch: missing $name"
    }
}
if (Test-Path -LiteralPath (Join-Path $root 'PREVIEW-STATUS.json')) {
    & (Join-Path $root 'Test-PreviewPackage.ps1') -PackageRoot $root
} elseif (Test-Path -LiteralPath (Join-Path $root 'manifest.json')) {
    & (Join-Path $root 'Test-ReleasePackage.ps1') -PackageRoot $root
} else {
    throw 'Would fail launch: no valid preview or finished-release manifest.'
}
$ports = @(5432,18765)
$listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
foreach ($port in $ports) {
    $matches = @($listeners | Where-Object {
        $_.Port -eq $port -and ($_.Address.ToString() -eq '127.0.0.1' -or
                                 $_.Address.ToString() -eq '0.0.0.0' -or
                                 $_.Address.ToString() -eq '::' -or
                                 $_.Address.ToString() -eq '::1')
    })
    if ($matches.Count -gt 0) {
        Write-Warning "Local TCP port $port is ALREADY LISTENING; verify the owner/expected service before any launch. No connection performed."
    } else {
        Write-Host "Port $port has no observed local TCP listener; check fresh setup/permission as appropriate."
    }
}
$venv = Join-Path $root 'database\.venv\Scripts\python.exe'
$marker = Join-Path $root 'database\.venv\kilos-offline-manifest.sha256'
if ($RequireOfflineRuntime -and (-not (Test-Path -LiteralPath $venv -PathType Leaf) -or
                                -not (Test-Path -LiteralPath $marker -PathType Leaf))) {
    throw 'NOT launch-ready: target-local Python 3.11 virtual environment/marker missing. Setup offline on destination first.'
}
Write-Host 'PASS read-only launch simulation: EXE/PCK and package integrity verified; NO game, camera, database or API started.'
