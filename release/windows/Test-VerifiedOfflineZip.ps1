# Read-only ZIP verification: entire archive entries must equal a finished release.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ZipPath,
    [string]$PackageRoot = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (-not $PackageRoot) { $PackageRoot = Join-Path $PSScriptRoot 'out\KilosGrammar-win-x64' }
$root = [IO.Path]::GetFullPath($PackageRoot)
& (Join-Path $PSScriptRoot 'Test-ReleasePackage.ps1') -PackageRoot $root
$manifest = Get-Content (Join-Path $root 'manifest.json') -Raw | ConvertFrom-Json
$files = @($manifest.files) + @([pscustomobject]@{
    path = 'manifest.json'
    bytes = (Get-Item (Join-Path $root 'manifest.json')).Length
    sha256 = (Get-FileHash (Join-Path $root 'manifest.json') -Algorithm SHA256).Hash
})
$archive = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($ZipPath))
try {
    if ($archive.Entries.Count -ne $files.Count) { throw "ZIP entry count mismatch: expected $($files.Count), actual $($archive.Entries.Count)" }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        foreach ($file in $files) {
            $entryName = 'KilosGrammar-win-x64/' + [string]$file.path
            $entry = $archive.GetEntry($entryName)
            if ($null -eq $entry -or -not $seen.Add($entryName)) { throw "ZIP entry missing or duplicated: $entryName" }
            if ($entry.Length -ne [long]$file.bytes) { throw "ZIP byte-size mismatch: $entryName" }
            $stream = $entry.Open()
            try { $digest = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') } finally { $stream.Dispose() }
            if ($digest -ne [string]$file.sha256) { throw "ZIP SHA256 mismatch: $entryName" }
        }
        foreach ($entry in $archive.Entries) {
            if (-not $seen.Contains($entry.FullName)) { throw "Unmanifested ZIP member: $($entry.FullName)" }
        }
    } finally { $sha.Dispose() }
} finally { $archive.Dispose() }
Write-Host "PASS finished offline ZIP: $($files.Count) exact, SHA256-verified entries. Clean-PC acceptance still required."
