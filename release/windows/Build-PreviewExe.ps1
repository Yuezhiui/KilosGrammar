# Real EXE + PCK fallback when official matching Windows export templates are
# missing. The EXE is the large Godot EDITOR tool binary; this is a developer
# preview ONLY, not an optimized/signed distributable game export or installer.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GodotExe,
    [Parameter(Mandatory=$true)][string]$EditorExe,
    [Parameter(Mandatory=$true)][string]$ModelPath,
    [string]$OutputDirectory = ''
)
$ErrorActionPreference='Stop'
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot 'staging\KilosGrammar-EDITOR-PREVIEW-win-x64' }
$target = [IO.Path]::GetFullPath($OutputDirectory)
$releaseRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\','/') + '\'
if (-not $target.StartsWith($releaseRoot,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Preview output must remain under release/windows; do not write into project assets or arbitrary user locations.'
}
if (Test-Path -LiteralPath $target) { throw "Refusing to overwrite existing preview: $target" }
foreach ($file in @($GodotExe,$EditorExe,$ModelPath)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Required preview input absent: $file" }
}
$engine = ((& $GodotExe --version | Select-Object -First 1) -as [string]).Trim()
# The GUI-subsystem Godot editor EXE has no stdout attached on Windows;
# `--version` prints nothing. Its PE version resource is the reliable check.
$editor = [string](Get-Item -LiteralPath $EditorExe).VersionInfo.ProductVersion
if (-not $engine.StartsWith('4.7.2.stable') -or -not $editor.StartsWith('4.7.2.stable')) {
    throw 'Both binaries must be Godot 4.7.2 stable. Refusing mismatched editor tool binary.'
}
$stage = Join-Path $PSScriptRoot ('staging\preview-build-' + [Guid]::NewGuid().ToString('N'))
if (Test-Path -LiteralPath $stage) { throw 'Unique preview staging path already exists.' }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
function Copy-One([string]$relative) {
    $from = Join-Path $source $relative
    if (-not (Test-Path -LiteralPath $from -PathType Leaf)) { throw "Required source file absent: $relative" }
    $to = Join-Path $stage $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $to) -Force | Out-Null
    Copy-Item -LiteralPath $from -Destination $to
}
try {
    # --export-pack requires NO platform executable template. Do not fall back
    # to --export-release and do not call the resulting EXE a classroom build.
    # PowerShell 5.1 can treat warning text written to a native program's
    # stderr as a terminating ErrorRecord. Only the REAL exit code is fatal.
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $GodotExe --headless --path $source --export-pack 'Windows Desktop' (Join-Path $stage 'KilosGrammar.pck') 2>&1 |
            Out-File -LiteralPath (Join-Path $stage 'preview-build.log') -Encoding UTF8
        $exportExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($exportExit -ne 0) { throw 'Godot --export-pack failed; inspect preview-build.log. No release was published.' }
    Copy-Item -LiteralPath $EditorExe -Destination (Join-Path $stage 'KilosGrammar.exe')
    foreach ($relative in @(
        'database\__init__.py','database\config.py','database\storage.py',
        'database\recovery_store.py','database\server.py','database\xlsx_export.py','database\migrate.py',
        'database\requirements.txt','database\configure_local.ps1',
        'database\setup_from_game.ps1','database\setup_local.ps1',
        'database\run_local.ps1','database\start_auto.ps1',
        'database\migrations\001_initial.sql','database\migrations\002_add_minigame.sql',
        'ui\vision\pose_worker.py','ui\vision\student_lock.py','ui\vision\two_player_lock.py',
        'ui\vision\gesture_detector.py','ui\vision\requirements-pose.txt',
        'release\windows\branding\KILOSGRAMMAR.ico',
        'release\windows\branding\KILOSGRAMMAR.png'
    )) { Copy-One $relative }
    New-Item -ItemType Directory -Path (Join-Path $stage 'runtime\models') -Force | Out-Null
    Copy-Item -LiteralPath $ModelPath -Destination (Join-Path $stage 'runtime\models\yolo26n-pose.pt')
    foreach ($name in @('Test-PreviewPackage.ps1','Test-LaunchPreflight.ps1',
        'Install-Portable.ps1','Uninstall-Portable.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $stage $name)
    }
    @'
DEVELOPER-ONLY PREVIEW — NOT THE COMPLETE OFFLINE WINDOWS RELEASE
This EXE is an unoptimized Godot 4.7.2 editor binary paired with a genuine
exported KilosGrammar.pck. The source-staged YOLO model is included, but this
package DOES NOT INCLUDE Python 3.11 wheels/interpreter, PostgreSQL installer,
or an installed app environment. The EXE icon is the default editor icon;
the approved KILOSGRAMMAR.ico is in release/windows/branding and the export
preset is configured for it when real export templates are installed.

Do not distribute to a school. No second-PC cold/offline test has been done.
For the real release use Build-OfflineRelease.ps1 after all its prerequisites
are supplied and its integrity, permissions and first-install tests pass.
'@ | Set-Content -LiteralPath (Join-Path $stage 'NOT-DEPLOYABLE.txt') -Encoding UTF8
    # Don't ship the noisy build log; it contains build-machine absolute paths.
    Remove-Item -LiteralPath (Join-Path $stage 'preview-build.log')
    $prefix = [IO.Path]::GetFullPath($stage).TrimEnd('\','/') + '\'
    $inventory = @(Get-ChildItem -LiteralPath $stage -File -Recurse | Sort-Object FullName | ForEach-Object {
        [ordered]@{ path=$_.FullName.Substring($prefix.Length).Replace('\','/'); bytes=$_.Length;
                    sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    })
    $marker = [ordered]@{kind='KilosGrammarEditorPreviewOnly';deployable=$false;
        engine=$engine; format='Godot editor EXE paired with real external PCK';
        offlineDependenciesIncluded=$false; files=$inventory } | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $stage 'PREVIEW-STATUS.json'), $marker + "`n", (New-Object System.Text.UTF8Encoding($false)))
    & (Join-Path $PSScriptRoot 'Test-PreviewPackage.ps1') -PackageRoot $stage
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Move-Item -LiteralPath $stage -Destination $target
    & (Join-Path $PSScriptRoot 'Test-PreviewPackage.ps1') -PackageRoot $target
    Write-Host "PREVIEW ONLY: $target"
} catch {
    Write-Warning "Preview staging preserved for investigation: $stage"
    throw
}
