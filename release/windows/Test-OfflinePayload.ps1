# Read-only integrity and offline-prerequisite check. Returns an error instead
# of quietly downloading packages or installing PostgreSQL on the host.
[CmdletBinding()]
param(
    [string]$PayloadRoot = $PSScriptRoot,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$payload = [IO.Path]::GetFullPath($PayloadRoot)
$offline = Join-Path $payload 'offline'
$manifestPath = Join-Path $offline 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Offline payload manifest missing: $manifestPath. Run Stage-OfflinePrerequisites.ps1 first."
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 1 -or $manifest.python -ne '3.11' -or $manifest.platform -ne 'win_amd64') {
    throw 'Unsupported offline manifest schema, Python version or architecture.'
}
$offlineFull = [IO.Path]::GetFullPath($offline).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$entries = @($manifest.files)
if ($entries.Count -eq 0) { throw 'Empty offline manifest.' }
foreach ($item in $entries) {
    $relative = [string]$item.path
    if ($relative -notmatch '^[a-zA-Z0-9_./+() -]+$' -or
        $relative.StartsWith('/') -or $relative.Contains('..') -or $relative.Contains(':') -or
        -not $seen.Add($relative)) {
        throw "Invalid or duplicated manifest-relative path: $relative"
    }
    $candidate = [IO.Path]::GetFullPath((Join-Path $offline ($relative.Replace('/', '\'))))
    if (-not $candidate.StartsWith($offlineFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Invalid manifest location: $relative"
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw "Missing offline artifact: $relative" }
    $file = Get-Item -LiteralPath $candidate
    if ($file.Length -ne [long]$item.bytes) { throw "Size mismatch: $relative" }
    $actual = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
    if ($actual -ne [string]$item.sha256) { throw "SHA256 mismatch: $relative" }
}
$actualFiles = @(Get-ChildItem -LiteralPath $offline -File -Recurse | Where-Object { $_.FullName -ne $manifestPath })
if ($actualFiles.Count -ne $entries.Count) { throw 'Offline artifact set differs from the signed-off manifest. Re-stage explicitly.' }
$names = @($entries | ForEach-Object { [string]$_.path })
$essential = @(
    'models/yolo26n-pose.pt',
    'installers/python-3.11',
    'installers/postgresql-18',
    'wheels/psycopg',
    'wheels/psycopg_binary',
    'wheels/ultralytics',
    'wheels/torch-',
    'wheels/torchvision',
    'wheels/opencv_python',
    'wheels/lap-'
)
foreach ($required in $essential) {
    $match = @($names | Where-Object { $_.StartsWith($required, [StringComparison]::OrdinalIgnoreCase) })
    if ($match.Count -eq 0) { throw "Offline artifact missing ($required). Supply the full Windows CPython 3.11 x64 wheelhouse and installers." }
}
if (-not $Quiet) { Write-Host ("PASS offline payload: {0} files verified by SHA256, no network required." -f $entries.Count) }
