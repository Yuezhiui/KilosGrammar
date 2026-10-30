# Reproducible best-effort packaging of an existing verified developer preview.
# Never converts an incomplete preview into a fake installer/full offline release.
[CmdletBinding()]
param(
    [string]$PackageRoot = '',
    [string]$OutputZip = '',
    [switch]$AllowPreview
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not $PackageRoot) {
    $PackageRoot = Join-Path $PSScriptRoot 'staging\KilosGrammar-EDITOR-PREVIEW-win-x64-releaseQA'
}
$root = [IO.Path]::GetFullPath($PackageRoot)
if (-not $AllowPreview) {
    throw 'Explicit -AllowPreview required: this script does NOT create a complete classroom installer.'
}
& (Join-Path $root 'Test-PreviewPackage.ps1') -PackageRoot $root
$manifest = Get-Content -LiteralPath (Join-Path $root 'PREVIEW-STATUS.json') -Raw | ConvertFrom-Json
if ($manifest.deployable -ne $false -or $manifest.kind -cne 'KilosGrammarEditorPreviewOnly') {
    throw 'Only a verified NON-DEPLOYABLE preview may be packaged with this script.'
}
if (-not $OutputZip) {
    $version = (Get-Content -LiteralPath (Join-Path $source 'VERSION') -Raw).Trim()
    if ($version -cnotmatch '^\d+\.\d+\.\d+-beta\.\d+$') { throw "Unexpected version: $version" }
    $OutputZip = Join-Path $PSScriptRoot "out\KilosGrammar-v$version-EDITOR-PREVIEW-NOT-DEPLOYABLE-win-x64.zip"
}
$destination = [IO.Path]::GetFullPath($OutputZip)
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'out')).TrimEnd('\','/') + '\'
if (-not $destination.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'ZIP must be created under ignored release/windows/out only.'
}
if ((Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath "$destination.sha256.txt")) {
    throw "Refusing to overwrite a previous ZIP or checksum: $destination"
}
$payload = @($manifest.files | ForEach-Object { [string]$_.path }) + @('PREVIEW-STATUS.json')
$rootPrefix = $root.TrimEnd('\','/') + '\'
$zipPrefix = 'KilosGrammar-EDITOR-PREVIEW-NOT-DEPLOYABLE/'
New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
$stream = [IO.File]::Open($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
$archive = $null
try {
    $archive = New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
    foreach ($item in ($payload | Sort-Object)) {
        if ($item -notmatch '^[a-zA-Z0-9_./+() -]+$' -or $item.Contains('..') -or $item.Contains(':') -or $item.StartsWith('/')) {
            throw "Unsafe path in preview inventory: $item"
        }
        $path = [IO.Path]::GetFullPath((Join-Path $root ($item.Replace('/','\'))))
        if (-not $path.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required payload entry: $item" }
        $info = Get-Item -LiteralPath $path
        if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked input disallowed: $item" }
        $entry = $archive.CreateEntry(($zipPrefix+$item.Replace('\\','/')),[IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::Parse('2026-10-30T00:00:00+00:00')
        $from = [IO.File]::OpenRead($path)
        $to = $entry.Open()
        try { $from.CopyTo($to) }
        finally { $from.Dispose(); $to.Dispose() }
    }
} finally {
    if ($null -ne $archive) { $archive.Dispose() } else { $stream.Dispose() }
}
$digest = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
[IO.File]::WriteAllText("$destination.sha256.txt",("$digest  " + [IO.Path]::GetFileName($destination) + "`n"),
    (New-Object System.Text.UTF8Encoding($false)))
& (Join-Path $PSScriptRoot 'Test-ReviewedZip.ps1') -ZipPath $destination -PackageRoot $root -AllowPreview
Write-Host "PREVIEW-ZIP CREATED: $destination"
Write-Host "ZIP BYTES: $((Get-Item -LiteralPath $destination).Length)"
