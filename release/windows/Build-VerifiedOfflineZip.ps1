# Packages only a fully SHA-validated offline release. Never labels it clean-PC tested.
[CmdletBinding()]
param(
    [string]$PackageRoot = '',
    [string]$OutputZip = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
if (-not $PackageRoot) { $PackageRoot = Join-Path $PSScriptRoot 'out\KilosGrammar-win-x64' }
$root = [IO.Path]::GetFullPath($PackageRoot)
& (Join-Path $PSScriptRoot 'Test-ReleasePackage.ps1') -PackageRoot $root
$version = (Get-Content (Join-Path $PSScriptRoot '..\..\VERSION') -Raw).Trim()
if ($version -cnotmatch '^\d+\.\d+\.\d+-beta\.\d+$') { throw "Unrecognized beta version: $version" }
if (-not $OutputZip) {
    $OutputZip = Join-Path $PSScriptRoot "out\KilosGrammar-v$version-OFFLINE-CANDIDATE-NOT-CLEAN-PC-TESTED-win-x64.zip"
}
$dest = [IO.Path]::GetFullPath($OutputZip)
$outRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'out')).TrimEnd('\','/') + '\'
if (-not $dest.StartsWith($outRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'ZIP output must stay inside release/windows/out.' }
if ((Test-Path -LiteralPath $dest) -or (Test-Path -LiteralPath "$dest.sha256.txt")) { throw 'Refusing to overwrite existing ZIP or checksum.' }
$manifest = Get-Content (Join-Path $root 'manifest.json') -Raw | ConvertFrom-Json
$paths = @($manifest.files | ForEach-Object { [string]$_.path }) + @('manifest.json')
$rootPrefix = $root.TrimEnd('\','/') + '\'
$zipPrefix = 'KilosGrammar-win-x64/'
$stream = [IO.File]::Open($dest, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
$archive = $null
try {
    $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
    foreach ($relative in ($paths | Sort-Object)) {
        if ($relative -notmatch '^[a-zA-Z0-9_./+() -]+$' -or $relative.Contains('..') -or $relative.Contains(':') -or $relative.StartsWith('/')) { throw "Unsafe release path: $relative" }
        $path = [IO.Path]::GetFullPath((Join-Path $root $relative.Replace('/','\')))
        if (-not $path.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes release folder: $relative" }
        $file = Get-Item -LiteralPath $path
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked source disallowed: $relative" }
        $entry = $archive.CreateEntry($zipPrefix+$relative, [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::Parse('2026-10-30T00:00:00+00:00')
        $from = [IO.File]::OpenRead($path)
        $to = $entry.Open()
        try { $from.CopyTo($to) } finally { $to.Dispose(); $from.Dispose() }
    }
} finally {
    if ($null -ne $archive) { $archive.Dispose() } else { $stream.Dispose() }
}
& (Join-Path $PSScriptRoot 'Test-VerifiedOfflineZip.ps1') -ZipPath $dest -PackageRoot $root
$hash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
[IO.File]::WriteAllText("$dest.sha256.txt", "$hash  $([IO.Path]::GetFileName($dest))`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "CANDIDATE ZIP: $dest"
Write-Host "ZIP BYTES: $((Get-Item $dest).Length)"
Write-Host "ZIP SHA256: $hash"
