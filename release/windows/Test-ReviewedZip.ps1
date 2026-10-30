# Verifies an externally distributable ZIP is exactly the SHA-256 manifest-
# reviewed developer preview, without extracting or launching its contents.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ZipPath,
    [Parameter(Mandatory=$true)][string]$PackageRoot,
    [switch]$AllowPreview
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
$zip = [IO.Path]::GetFullPath($ZipPath)
$root = [IO.Path]::GetFullPath($PackageRoot)
if (-not (Test-Path -LiteralPath $zip -PathType Leaf)) { throw "ZIP not found: $zip" }
if (-not $AllowPreview) { throw 'Developer preview ZIP requires explicit -AllowPreview; this is NOT a school installer.' }
& (Join-Path $root 'Test-PreviewPackage.ps1') -PackageRoot $root
$marker = Get-Content -LiteralPath (Join-Path $root 'PREVIEW-STATUS.json') -Raw | ConvertFrom-Json
if ($marker.deployable -ne $false -or $marker.kind -cne 'KilosGrammarEditorPreviewOnly') {
    throw 'Only a non-deployable developer preview can use this specific ZIP verifier.'
}
$prefix = 'KilosGrammar-EDITOR-PREVIEW-NOT-DEPLOYABLE/'
$expected = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($file in @($marker.files)) {
    $key = $prefix + [string]$file.path
    if ($expected.ContainsKey($key)) { throw "Duplicated manifest entry: $key" }
    $expected.Add($key,[string]$file.sha256)
}
$markerPath = Join-Path $root 'PREVIEW-STATUS.json'
$expected.Add(($prefix + 'PREVIEW-STATUS.json'), (Get-FileHash -LiteralPath $markerPath -Algorithm SHA256).Hash)
$sidecar = "$zip.sha256.txt"
if (-not (Test-Path -LiteralPath $sidecar -PathType Leaf)) { throw "ZIP checksum sidecar absent: $sidecar" }
$writtenHash = ((Get-Content -LiteralPath $sidecar -Raw).Trim() -split '\s+')[0]
$actualHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
if ($writtenHash -cne $actualHash) { throw 'ZIP SHA256 sidecar mismatch.' }
$reader = [IO.File]::OpenRead($zip)
$archive = $null
$hasher = [Security.Cryptography.SHA256]::Create()
try {
    $archive = New-Object IO.Compression.ZipArchive($reader,[IO.Compression.ZipArchiveMode]::Read,$false)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $archive.Entries) {
        if ($entry.FullName.EndsWith('/')) { throw "Unexpected ZIP directory entry: $($entry.FullName)" }
        if (-not $entry.FullName.StartsWith($prefix,[StringComparison]::Ordinal) -or
            $entry.FullName.Contains('..') -or $entry.FullName.Contains('\\') -or
            $entry.FullName.Contains(':') -or -not $expected.ContainsKey($entry.FullName) -or
            -not $seen.Add($entry.FullName)) { throw "Unexpected or unsafe ZIP entry: $($entry.FullName)" }
        $file = $entry.Open()
        try { $hash = [BitConverter]::ToString($hasher.ComputeHash($file)).Replace('-','') }
        finally { $file.Dispose() }
        if ($hash -cne $expected[$entry.FullName]) { throw "ZIP entry SHA256 mismatch: $($entry.FullName)" }
    }
    if ($seen.Count -ne $expected.Count) {
        throw "ZIP file count does not match audited payload: $($seen.Count) vs $($expected.Count)"
    }
} finally {
    if ($null -ne $archive) { $archive.Dispose() } else { $reader.Dispose() }
    $hasher.Dispose()
}
Write-Host "PASS ZIP validated: $($expected.Count) exact, SHA256-matched preview entries; archive SHA256=$actualHash"
Write-Warning 'Developer preview ONLY, no Python/PG offline installers or wheelhouse: NOT ready for classroom deployment or a production GitHub Release.'
