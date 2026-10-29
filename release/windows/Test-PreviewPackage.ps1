# Read-only verification of an explicitly NON-DEPLOYABLE editor-tool preview.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PackageRoot)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($PackageRoot)
$manifestPath = Join-Path $root 'PREVIEW-STATUS.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw 'Preview marker absent; do not treat this folder as a preview or official release.'
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.kind -cne 'KilosGrammarEditorPreviewOnly' -or $manifest.deployable -ne $false) {
    throw 'Invalid preview marker. Full school release requires a different validated manifest.'
}
$expected = @($manifest.files)
if ($expected.Count -lt 4) { throw 'Preview contains too few files.' }
$rootPrefix = $root.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($file in $expected) {
    $name = [string]$file.path
    if ($name -notmatch '^[a-zA-Z0-9_./+() -]+$' -or $name.Contains('..') -or
        $name.StartsWith('/') -or $name.Contains(':') -or -not $seen.Add($name)) {
        throw "Unsafe or duplicate preview file: $name"
    }
    $path = [IO.Path]::GetFullPath((Join-Path $root ($name.Replace('/','\'))))
    if (-not $path.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing preview file: $name" }
    $info = Get-Item -LiteralPath $path
    if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Unexpected linked preview file: $name" }
    if ($info.Length -ne [long]$file.bytes -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne [string]$file.sha256) {
        throw "Preview file does not match SHA256: $name"
    }
}
foreach ($essential in @('KilosGrammar.exe','KilosGrammar.pck','ui/vision/pose_worker.py',
    'database/server.py','database/recovery_store.py','runtime/models/yolo26n-pose.pt')) {
    if (-not $seen.Contains($essential)) { throw "Essential preview file absent: $essential" }
}
$actual = @(Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object {
    $_.FullName -ne $manifestPath -and $_.FullName -ne (Join-Path $root '.kilos-install.json')
})
if ($actual.Count -ne $expected.Count) { throw 'Preview has extra/missing unverified files.' }
if (Test-Path -LiteralPath (Join-Path $root 'manifest.json')) {
    throw 'Preview cannot claim the finished-release manifest.json.'
}
Write-Host "PASS preview SHA256: $($expected.Count) files. WARNING: editor runner, no offline installers/wheels; NOT classroom deployable."
