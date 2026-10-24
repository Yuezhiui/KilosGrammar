# Stage only real, already-reviewed offline prerequisites. The manifest is
# published only after complete files have passed a read-only SHA256 check.
# No network, installer, database changes, user-state changes, or overwrite.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ModelPath,
    [Parameter(Mandatory=$true)][string]$PythonInstallerPath,
    [Parameter(Mandatory=$true)][string]$PostgreSqlInstallerPath,
    [Parameter(Mandatory=$true)][string]$WheelhouseDirectory,
    [string]$LicenseDirectory = ''
)

$ErrorActionPreference = 'Stop'
$offline = Join-Path $PSScriptRoot 'offline'
if (Test-Path -LiteralPath $offline) {
    if (Test-Path -LiteralPath (Join-Path $offline 'manifest.json') -PathType Leaf) {
        & (Join-Path $PSScriptRoot 'Test-OfflinePayload.ps1') -PayloadRoot $PSScriptRoot
    }
    throw "An offline staging directory already exists: $offline. It has been preserved. Inspect and archive or explicitly relocate it before starting a new staging run."
}
if (-not (Test-Path -LiteralPath $ModelPath -PathType Leaf)) { throw "Model file not found: $ModelPath" }
if (-not (Test-Path -LiteralPath $PythonInstallerPath -PathType Leaf)) { throw "Python offline installer not found: $PythonInstallerPath" }
if (-not (Test-Path -LiteralPath $PostgreSqlInstallerPath -PathType Leaf)) { throw "PostgreSQL offline installer not found: $PostgreSqlInstallerPath" }
if ((Split-Path -Leaf $PythonInstallerPath) -notmatch '^python-3\.11\.[0-9]+-amd64\.exe$') {
    throw 'Expected a vetted CPython 3.11 x64 full installer named python-3.11.*-amd64.exe.'
}
if ((Split-Path -Leaf $PostgreSqlInstallerPath) -notmatch '^postgresql-18[^\\/]*-windows-x64\.exe$') {
    throw 'Expected a vetted PostgreSQL 18 x64 Windows installer named postgresql-18*-windows-x64.exe.'
}
if (-not (Test-Path -LiteralPath $WheelhouseDirectory -PathType Container)) { throw "Wheelhouse directory does not exist: $WheelhouseDirectory" }
$wheels = @(Get-ChildItem -LiteralPath $WheelhouseDirectory -Filter '*.whl' -File | Sort-Object Name)
if ($wheels.Count -eq 0) { throw 'Wheelhouse is empty. Stage ALL Windows CPython 3.11 x64 transitive wheels.' }
if ($LicenseDirectory -and -not (Test-Path -LiteralPath $LicenseDirectory -PathType Container)) {
    throw "License directory does not exist: $LicenseDirectory"
}

# All preparation takes place in a unique folder owned by this invocation.
# The normal offline/ location remains absent until validation succeeds.
$candidate = Join-Path $PSScriptRoot ('staging\offline-payload-' + [Guid]::NewGuid().ToString('N'))
$tempOffline = Join-Path $candidate 'offline'
function Copy-Approved([string]$src, [string]$relative) {
    $target = Join-Path $tempOffline $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $src -Destination $target -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash) {
        throw "Staged file checksum does not match source: $relative"
    }
}

try {
    New-Item -ItemType Directory -Path $tempOffline -Force | Out-Null
    Copy-Approved $ModelPath 'models\yolo26n-pose.pt'
    Copy-Approved $PythonInstallerPath ('installers\' + (Split-Path -Leaf $PythonInstallerPath))
    Copy-Approved $PostgreSqlInstallerPath ('installers\' + (Split-Path -Leaf $PostgreSqlInstallerPath))
    foreach ($wheel in $wheels) { Copy-Approved $wheel.FullName ('wheels\' + $wheel.Name) }
    if ($LicenseDirectory) {
        $licensePrefix = [IO.Path]::GetFullPath($LicenseDirectory).TrimEnd('\', '/') + '\'
        foreach ($license in @(Get-ChildItem -LiteralPath $LicenseDirectory -Recurse -File | Sort-Object FullName)) {
            if (-not $license.FullName.StartsWith($licensePrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Invalid license path: $($license.FullName)"
            }
            $suffix = $license.FullName.Substring($licensePrefix.Length)
            Copy-Approved $license.FullName (Join-Path 'licenses' $suffix)
        }
    }
    $prefix = [IO.Path]::GetFullPath($tempOffline).TrimEnd('\', '/') + '\'
    $entries = @(
        Get-ChildItem -LiteralPath $tempOffline -File -Recurse | Sort-Object FullName | ForEach-Object {
            [ordered]@{
                path = $_.FullName.Substring($prefix.Length).Replace('\', '/')
                bytes = $_.Length
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        }
    )
    $manifest = [ordered]@{
        schema = 1
        python = '3.11'
        platform = 'win_amd64'
        files = $entries
    } | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $tempOffline 'manifest.json'), $manifest + "`n", (New-Object System.Text.UTF8Encoding($false)))
    & (Join-Path $PSScriptRoot 'Test-OfflinePayload.ps1') -PayloadRoot $candidate
    if (Test-Path -LiteralPath $offline) { throw 'Offline output appeared during staging; preserved both folders for review.' }
    Move-Item -LiteralPath $tempOffline -Destination $offline
    & (Join-Path $PSScriptRoot 'Test-OfflinePayload.ps1') -PayloadRoot $PSScriptRoot
    Write-Host "Offline prerequisites published with verified SHA256 manifest: $(Join-Path $offline 'manifest.json')"
} finally {
    # Only our uniquely generated temporary subtree may be cleaned up.
    # A failed publication is never silently converted into a release manifest.
    if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate -Recurse -Force }
}
