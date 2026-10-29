# Non-admin, per-user portable folder installer. Never installs PostgreSQL,
# touches a database, copies DPAPI data, or writes under Program Files.
[CmdletBinding()]
param(
    [string]$PackageRoot = $PSScriptRoot,
    [string]$Destination = '',
    [switch]$AllowPreview,
    [switch]$Simulate
)
$ErrorActionPreference = 'Stop'
if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA required for a safe per-user install.' }
$programs = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs')).TrimEnd('\','/')
if (-not $Destination) { $Destination = Join-Path $programs 'KilosGrammar' }
$target = [IO.Path]::GetFullPath($Destination)
if (-not $target.StartsWith($programs+'\',[StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing install outside per-user LOCALAPPDATA Programs: $target"
}
if (Test-Path -LiteralPath $target) { throw "Destination must be FRESH, existing install preserved: $target" }
$source = [IO.Path]::GetFullPath($PackageRoot)
if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "Package absent: $source" }
if ($source -eq $target) { throw 'Package source and destination must differ.' }
if (Test-Path -LiteralPath (Join-Path $source 'PREVIEW-STATUS.json')) {
    if (-not $AllowPreview) { throw 'Editor-preview EXE/PCK is NOT a finished school release. Explicit -AllowPreview required.' }
    & (Join-Path $source 'Test-PreviewPackage.ps1') -PackageRoot $source
    $kind = 'developer-preview-only'
} else {
    if (-not (Test-Path -LiteralPath (Join-Path $source 'manifest.json') -PathType Leaf)) {
        throw 'Full offline export manifest missing; refusing unverified installation.'
    }
    & (Join-Path $source 'Test-ReleasePackage.ps1') -PackageRoot $source
    $kind = 'validated-offline-payload-not-clean-PC-certified'
}
$sourcePrefix = $source.TrimEnd('\','/') + '\'
$files = @(Get-ChildItem -LiteralPath $source -Recurse -File -Force)
if (-not $files.Count) { throw 'Empty source release folder.' }
foreach ($item in @(Get-ChildItem -LiteralPath $source -Recurse -Force)) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Linked/reparse-point release input is forbidden: $($item.FullName)"
    }
}
if ($Simulate) {
    Write-Host "PASS simulated install ${kind}: would copy $($files.Count) verified files to fresh $target; no database, registry or user data writes."
    return
}
New-Item -ItemType Directory -Path $programs -Force | Out-Null
$temporary = Join-Path $programs ('KilosGrammar-InstallStaging-' + [Guid]::NewGuid().ToString('N'))
if (Test-Path -LiteralPath $temporary) { throw 'Unique staging name collision.' }
$published = $false
try {
    New-Item -ItemType Directory -Path $temporary | Out-Null
    $inventory = @()
    foreach ($item in ($files | Sort-Object FullName)) {
        $relative = $item.FullName.Substring($sourcePrefix.Length)
        $to = Join-Path $temporary $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $to) -Force | Out-Null
        Copy-Item -LiteralPath $item.FullName -Destination $to -ErrorAction Stop
        $digest = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        if ((Get-FileHash -LiteralPath $to -Algorithm SHA256).Hash -ne $digest) {
            throw "Copied file SHA256 mismatch: $relative"
        }
        $inventory += [ordered]@{path=$relative.Replace('\','/');bytes=$item.Length;sha256=$digest}
    }
    $record = [ordered]@{schema=1;kind='KilosGrammarPerUserInstall';packageKind=$kind;files=$inventory} |
        ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $temporary '.kilos-install.json'), $record + "`n",
        (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $target) { throw 'Install destination appeared during staging. Preserved.' }
    Move-Item -LiteralPath $temporary -Destination $target
    $published = $true
    Write-Host "PASS installed $kind at $target"
    Write-Host 'Student records, Godot saves and DPAPI credentials remain OUTSIDE the installed program folder.'
    if ($kind -eq 'developer-preview-only') { Write-Warning 'This is an incomplete developer preview. It lacks the offline Python/PostgreSQL installers and wheels.' }
} finally {
    if (-not $published -and (Test-Path -LiteralPath $temporary)) {
        # Only our unique, invocation-owned staging folder can be removed.
        Remove-Item -LiteralPath $temporary -Recurse -Force
    }
}
