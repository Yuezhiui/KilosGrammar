# Safe per-user uninstall: refuse unknown/modified files and never delete
# %LOCALAPPDATA%\KilosGrammar credentials or Godot user:// saved data.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Destination,[switch]$Simulate)
$ErrorActionPreference='Stop'
$programs = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs')).TrimEnd('\','/')
$target = [IO.Path]::GetFullPath($Destination)
if (-not $target.StartsWith($programs+'\',[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing uninstall outside per-user LOCALAPPDATA Programs.'
}
if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw 'Installed directory absent.' }
if ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'Refusing to follow a linked installation directory.'
}
$journal = Join-Path $target '.kilos-install.json'
if (-not (Test-Path -LiteralPath $journal -PathType Leaf)) { throw 'Not a managed portable install: journal missing.' }
$record = Get-Content -LiteralPath $journal -Raw | ConvertFrom-Json
if ($record.schema -ne 1 -or $record.kind -cne 'KilosGrammarPerUserInstall') { throw 'Unexpected install journal.' }
$files = @($record.files)
$expected = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$prefix = $target.TrimEnd('\','/') + '\'
foreach ($file in $files) {
    $relative = [string]$file.path
    if ($relative -notmatch '^[a-zA-Z0-9_./+() -]+$' -or $relative.Contains('..') -or
        $relative.StartsWith('/') -or $relative.Contains(':') -or -not $expected.Add($relative)) {
        throw 'Unsafe entry in install journal.'
    }
    $absolute = [IO.Path]::GetFullPath((Join-Path $target ($relative.Replace('/','\'))))
    if (-not $absolute.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "Installed file missing: $relative" }
    if ((Get-Item -LiteralPath $absolute).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Linked installed file not removable: $relative"
    }
    if ((Get-Item -LiteralPath $absolute).Length -ne [long]$file.bytes -or
        (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash -cne [string]$file.sha256) {
        throw "Installed file changed; refusing destructive uninstall: $relative"
    }
}
$actual = @(Get-ChildItem -LiteralPath $target -Recurse -File -Force | Where-Object { $_.FullName -ne $journal })
if ($actual.Count -ne $files.Count) { throw 'Unknown file(s) in install directory; refusing to remove potentially personal data.' }
if (@(Get-ChildItem -LiteralPath $target -Recurse -Directory -Force | Where-Object {
    ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
}).Count -gt 0) { throw 'Unknown linked directory found; refusing uninstall.' }
if ($Simulate) {
    Write-Host "PASS simulated uninstall: verified $($files.Count) unchanged install files at $target. External user data untouched."
    return
}
Remove-Item -LiteralPath $target -Recurse -Force
Write-Host "PASS removed only verified application install folder: $target"
Write-Host 'Preserved external player saves, per-user PostgreSQL credentials, logs and pose model cache.'
