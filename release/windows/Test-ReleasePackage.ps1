# Read-only verification of a FINISHED exported Windows release directory.
# Unlike offline/manifest.json, root manifest.json is created only after the
# Godot EXE/PCK exist and all release files have been staged.
[CmdletBinding()]
param([string]$PackageRoot = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = Join-Path $PSScriptRoot 'out\KilosGrammar-win-x64'
}
$root = [IO.Path]::GetFullPath($PackageRoot)
$manifestPath = Join-Path $root 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Finished release manifest missing: $manifestPath. A completed export does not exist at this path. Run Build-WindowsRelease.ps1 after staging verified offline prerequisites and installing Godot 4.7.2 export templates; never generate an empty or fabricated manifest."
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 1 -or $manifest.kind -ne 'KilosGrammarWindowsRelease' -or $manifest.engine -notlike '4.7.2.stable*') {
    throw 'Invalid finished-release manifest schema, kind, or Godot engine version.'
}
$rootPrefix = $root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$entries = @($manifest.files)
if ($entries.Count -eq 0) { throw 'Finished release contains no files in its manifest.' }
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $entries) {
    $relative = [string]$entry.path
    if ($relative -notmatch '^[a-zA-Z0-9_./+() -]+$' -or $relative.StartsWith('/') -or
        $relative.Contains('..') -or $relative.Contains(':') -or -not $seen.Add($relative)) {
        throw "Invalid or repeated finished-release file path: $relative"
    }
    $absolute = [IO.Path]::GetFullPath((Join-Path $root ($relative.Replace('/', '\'))))
    if (-not $absolute.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Invalid file path: $relative" }
    if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "Finished release artifact missing: $relative" }
    if ((Get-Item -LiteralPath $absolute).Length -ne [long]$entry.bytes) { throw "Finished release file size mismatch: $relative" }
    if ((Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash -ne [string]$entry.sha256) {
        throw "Finished release SHA256 mismatch: $relative"
    }
}
$actual = @(Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object {
    $_.FullName -ne $manifestPath -and $_.FullName -ne (Join-Path $root '.kilos-install.json')
})
if ($actual.Count -ne $entries.Count) { throw 'The finished release contains missing or unexpected files not listed in manifest.json.' }
$essential = @(
    'KilosGrammar.exe', 'KilosGrammar.pck', 'offline/manifest.json',
    'release-manifest.json', 'database/start_auto.ps1', 'database/setup_from_game.ps1',
    'database/recovery_store.py', 'database/migrations/002_add_minigame.sql',
    'ui/vision/pose_worker.py', 'ui/vision/student_lock.py',
    'runtime/models/yolo26n-pose.pt', 'Play KilosGrammar.cmd', 'Setup Offline.cmd'
)
foreach ($relative in $essential) {
    if (-not $seen.Contains($relative)) { throw "Required finished-release file absent from manifest: $relative" }
}
if ((Get-Item -LiteralPath (Join-Path $root 'KilosGrammar.exe')).Length -lt 100000 -or
    (Get-Item -LiteralPath (Join-Path $root 'KilosGrammar.pck')).Length -lt 1000) {
    throw 'EXE/PCK too small for an export; refuse incomplete release.'
}
$metadata = Get-Content -LiteralPath (Join-Path $root 'release-manifest.json') -Raw | ConvertFrom-Json
foreach ($check in @(
    @{path='KilosGrammar.exe';digest=[string]$metadata.exe_sha256},
    @{path='KilosGrammar.pck';digest=[string]$metadata.pck_sha256},
    @{path='runtime/models/yolo26n-pose.pt';digest=[string]$metadata.pose_model_sha256},
    @{path='offline/manifest.json';digest=[string]$metadata.offline_manifest_sha256}
)) {
    $checkPath = Join-Path $root ($check.path.Replace('/', '\'))
    if ((Get-FileHash -LiteralPath $checkPath -Algorithm SHA256).Hash -ne $check.digest) {
        throw "Release metadata SHA256 disagrees with packaged file: $($check.path)"
    }
}
& (Join-Path $root 'Test-OfflinePayload.ps1') -PayloadRoot $root -Quiet
Write-Host ("PASS finished Windows release: {0} real files SHA256-verified, plus complete offline prerequisites." -f $entries.Count)
