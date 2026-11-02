# Reproducible Windows x64 Godot export plus loose offline service payload.
# Nothing is installed, and PostgreSQL/user credentials are never accessed.
[CmdletBinding()]
param(
    [string]$GodotExe = '',
    [string]$PythonExe = '',
    [string]$BuildLabel = '',
    [switch]$PreflightOnly
)

$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$outputRoot = Join-Path $PSScriptRoot 'out'
if ($BuildLabel -and $BuildLabel -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,69}$') {
    throw 'BuildLabel must be 1..70 safe ASCII letters, numbers, hyphen, underscore or dot (starting with a letter or number).'
}
$packageName = 'KilosGrammar-win-x64' + $(if ($BuildLabel) { '-' + $BuildLabel } else { '' })
$stage = Join-Path $PSScriptRoot ('staging\' + $packageName)
$final = Join-Path $outputRoot $packageName
$manifestSource = Join-Path $PSScriptRoot 'offline\manifest.json'

if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    $found = Get-Command 'godot.exe','Godot_v4.7.2-stable_win64_console.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $found) { $GodotExe = $found.Source }
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw 'Godot 4.7.2 console executable missing. Supply -GodotExe with the actual path to the installed editor/console build.'
}
$engineVersion = ((& $GodotExe --version) | Select-Object -First 1).Trim()
if ($LASTEXITCODE -ne 0 -or -not $engineVersion.StartsWith('4.7.2.stable')) {
    throw "Expected Godot 4.7.2 stable (project runtime), found: $engineVersion"
}
$templates = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Godot\export_templates\4.7.2.stable'
$templateExe = Join-Path $templates 'windows_release_x86_64.exe'
$debugTemplate = Join-Path $templates 'windows_debug_x86_64.exe'
$missing = @()
foreach ($template in @($templateExe, $debugTemplate)) {
    if (-not (Test-Path -LiteralPath $template -PathType Leaf)) {
        $missing += "Godot 4.7.2 Windows export template missing: $template"
    }
}
if (-not (Test-Path -LiteralPath $manifestSource -PathType Leaf)) {
    $missing += "Offline inputs have not been staged: $manifestSource. Obtain and review the model, CPython 3.11 installer, PostgreSQL 18 installer and all Windows x64 wheels, then run Stage-OfflinePrerequisites.ps1."
}
if ($missing.Count -gt 0) {
    throw ("Windows release preflight BLOCKED; no EXE/PCK or manifest generated:`n - " + ($missing -join "`n - "))
}
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'export_presets.cfg') -PathType Leaf)) {
    throw 'Windows Desktop preset missing: export_presets.cfg.'
}
& (Join-Path $PSScriptRoot 'Test-OfflinePayload.ps1') -PayloadRoot $PSScriptRoot
& (Join-Path $PSScriptRoot 'Test-OfflineWheels.ps1') -PythonExe $PythonExe
$required = @(
    'database\server.py', 'database\recovery_store.py', 'database\start_auto.ps1', 'database\setup_from_game.ps1',
    'database\configure_local.ps1', 'database\migrations\001_initial.sql',
    'ui\vision\pose_worker.py', 'ui\vision\student_lock.py', 'ui\vision\gesture_detector.py',
    'assets\fonts\TitanOne-Regular.ttf', 'assets\fonts\Comic Lemon.otf'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $relative) -PathType Leaf)) {
        throw "Release source missing: $relative"
    }
}
if ((Test-Path -LiteralPath $final) -or (Test-Path -LiteralPath $stage)) {
    throw "An output/staging folder already exists: $final or $stage. Preserve it; inspect/rename it before rebuilding."
}
Write-Host "PASS build prerequisites: $engineVersion, matching Windows template, source helpers, complete offline payload."
if ($PreflightOnly) { return }

New-Item -ItemType Directory -Force -Path $stage | Out-Null
Push-Location $sourceRoot
try {
    # --export-release uses the pinned Windows Desktop preset. Keep PCK external:
    # Python scripts referenced through ProjectSettings.globalize_path(res://)
    # must exist as normal files beside the exported EXE at runtime.
    & $GodotExe --headless --path $sourceRoot --export-release 'Windows Desktop' (Join-Path $stage 'KilosGrammar.exe')
    if ($LASTEXITCODE -ne 0) { throw "Godot --export-release failed with exit code $LASTEXITCODE." }
} finally {
    Pop-Location
}
$exportedExe = Join-Path $stage 'KilosGrammar.exe'
$exportedPck = Join-Path $stage 'KilosGrammar.pck'
if (-not (Test-Path -LiteralPath $exportedExe -PathType Leaf) -or
    -not (Test-Path -LiteralPath $exportedPck -PathType Leaf) -or
    (Get-Item -LiteralPath $exportedExe).Length -lt 100000 -or
    (Get-Item -LiteralPath $exportedPck).Length -lt 1000) {
    throw 'Godot export did not produce a valid executable and external data PCK.'
}

function Copy-One([string]$relative) {
    $src = Join-Path $sourceRoot $relative
    $dest = Join-Path $stage $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
    Copy-Item -LiteralPath $src -Destination $dest
}
# Only the backend and worker files needed by exported process launches.
foreach ($relative in @(
    'database\__init__.py', 'database\config.py', 'database\storage.py', 'database\recovery_store.py',
    'database\server.py', 'database\xlsx_export.py', 'database\migrate.py', 'database\requirements.txt',
    'database\configure_local.ps1', 'database\setup_from_game.ps1',
    'database\setup_local.ps1', 'database\run_local.ps1',
    'database\start_auto.ps1', 'database\README.md',
    'database\migrations\001_initial.sql', 'database\migrations\002_add_minigame.sql',
    'ui\vision\pose_worker.py', 'ui\vision\student_lock.py', 'ui\vision\two_player_lock.py', 'ui\vision\gesture_detector.py',
    'ui\vision\requirements-pose.txt'
)) { Copy-One $relative }

foreach ($name in @(
    'Test-OfflinePayload.ps1','Test-ReleasePackage.ps1','Install-OnSchoolPC.ps1','Launch-Game.ps1',
    'Test-LaunchPreflight.ps1','Install-Portable.ps1','Uninstall-Portable.ps1',
    'requirements-offline.txt','Play KilosGrammar.cmd','Setup Offline.cmd'
)) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $stage $name)
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'offline') -Destination (Join-Path $stage 'offline') -Recurse
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'runtime\models') | Out-Null
Copy-Item -LiteralPath (Join-Path $stage 'offline\models\yolo26n-pose.pt') -Destination (Join-Path $stage 'runtime\models\yolo26n-pose.pt')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination (Join-Path $stage 'RELEASE-INSTRUCTIONS.md')

& (Join-Path $stage 'Test-OfflinePayload.ps1') -PayloadRoot $stage
$releaseManifest = [ordered]@{
    engine=$engineVersion
    preset='Windows Desktop'
    python='3.11'
    architecture='x86_64'
    offline_manifest_sha256=(Get-FileHash -LiteralPath $manifestSource -Algorithm SHA256).Hash
    exe_sha256=(Get-FileHash -LiteralPath $exportedExe -Algorithm SHA256).Hash
    pck_sha256=(Get-FileHash -LiteralPath $exportedPck -Algorithm SHA256).Hash
    pose_model_sha256=(Get-FileHash -LiteralPath (Join-Path $stage 'runtime\models\yolo26n-pose.pt') -Algorithm SHA256).Hash
} | ConvertTo-Json -Depth 3
[IO.File]::WriteAllText((Join-Path $stage 'release-manifest.json'), $releaseManifest + "`n", (New-Object System.Text.UTF8Encoding($false)))
# The release root's canonical manifest MUST describe existing bytes, never
# template paths or hypothetical artifacts. The ignored offline/manifest.json
# has a separate purpose: it attests to input installers/wheels/model.
$releasePrefix = [IO.Path]::GetFullPath($stage).TrimEnd('\', '/') + '\'
$releaseFiles = @(
    Get-ChildItem -LiteralPath $stage -File -Recurse | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            path = $_.FullName.Substring($releasePrefix.Length).Replace('\', '/')
            bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    }
)
$rootManifest = [ordered]@{
    schema = 1
    kind = 'KilosGrammarWindowsRelease'
    engine = $engineVersion
    platform = 'win_amd64'
    files = $releaseFiles
} | ConvertTo-Json -Depth 6
[IO.File]::WriteAllText((Join-Path $stage 'manifest.json'), $rootManifest + "`n", (New-Object System.Text.UTF8Encoding($false)))
& (Join-Path $stage 'Test-ReleasePackage.ps1') -PackageRoot $stage
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
Move-Item -LiteralPath $stage -Destination $final
& (Join-Path $final 'Test-ReleasePackage.ps1') -PackageRoot $final
Write-Host "SUCCESS. Offline Windows release prepared: $final"
Write-Host 'Transfer the COMPLETE folder to a school PC; run Setup Offline.cmd there, then Play KilosGrammar.cmd.'
