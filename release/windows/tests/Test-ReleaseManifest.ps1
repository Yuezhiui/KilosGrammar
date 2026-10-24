# Synthetic positive/negative checks for the finished-release verifier.
# Fake EXE/PCK bytes are written only to a uniquely owned QA fixture, never
# to release/windows/out/ or the production offline prerequisites directory.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$releaseRoot = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $releaseRoot ('staging\release-manifest-qa-' + [Guid]::NewGuid().ToString('N'))
if (Test-Path -LiteralPath $fixture) { throw 'Refusing to overwrite an existing QA fixture.' }
try {
    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
    $inputs = @(
        'offline/models/yolo26n-pose.pt',
        'offline/installers/python-3.11.9-amd64.exe',
        'offline/installers/postgresql-18.0-1-windows-x64.exe',
        'offline/wheels/psycopg-3.3.6-py3-none-any.whl',
        'offline/wheels/psycopg_binary-3.3.6-cp311-cp311-win_amd64.whl',
        'offline/wheels/ultralytics-8.4.142-py3-none-any.whl',
        'offline/wheels/torch-2.6.0-cp311-cp311-win_amd64.whl',
        'offline/wheels/torchvision-0.21.0-cp311-cp311-win_amd64.whl',
        'offline/wheels/opencv_python-5.0.0.93-cp311-cp311-win_amd64.whl',
        'offline/wheels/lap-0.5.13-cp311-cp311-win_amd64.whl'
    )
    $inventory = @()
    foreach ($relative in $inputs) {
        $path = Join-Path $fixture ($relative.Replace('/', '\'))
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        [IO.File]::WriteAllText($path, 'QA fixture only; never a real installer or wheel: ' + $relative)
        $inventory += [ordered]@{
            path = $relative.Substring('offline/'.Length)
            bytes = (Get-Item -LiteralPath $path).Length
            sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        }
    }
    $offlineManifest = [ordered]@{schema=1;python='3.11';platform='win_amd64';files=$inventory} | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $fixture 'offline\manifest.json'), $offlineManifest, (New-Object System.Text.UTF8Encoding($false)))
    foreach ($relative in @(
        'database/start_auto.ps1','database/setup_from_game.ps1',
        'ui/vision/pose_worker.py','ui/vision/student_lock.py',
        'Play KilosGrammar.cmd','Setup Offline.cmd'
    )) {
        $path = Join-Path $fixture ($relative.Replace('/', '\'))
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        [IO.File]::WriteAllText($path, 'QA-only fixture: ' + $relative)
    }
    Copy-Item -LiteralPath (Join-Path $releaseRoot 'Test-OfflinePayload.ps1') -Destination (Join-Path $fixture 'Test-OfflinePayload.ps1')
    Copy-Item -LiteralPath (Join-Path $releaseRoot 'Test-ReleasePackage.ps1') -Destination (Join-Path $fixture 'Test-ReleasePackage.ps1')
    $model = Join-Path $fixture 'runtime\models\yolo26n-pose.pt'
    New-Item -ItemType Directory -Path (Split-Path -Parent $model) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $fixture 'offline\models\yolo26n-pose.pt') -Destination $model
    [IO.File]::WriteAllBytes((Join-Path $fixture 'KilosGrammar.exe'), (New-Object byte[] 120001))
    [IO.File]::WriteAllBytes((Join-Path $fixture 'KilosGrammar.pck'), (New-Object byte[] 2001))
    $metadata = [ordered]@{
        engine='4.7.2.stable.official.TEST-FIXTURE'
        preset='Windows Desktop'
        offline_manifest_sha256=(Get-FileHash (Join-Path $fixture 'offline\manifest.json') -Algorithm SHA256).Hash
        exe_sha256=(Get-FileHash (Join-Path $fixture 'KilosGrammar.exe') -Algorithm SHA256).Hash
        pck_sha256=(Get-FileHash (Join-Path $fixture 'KilosGrammar.pck') -Algorithm SHA256).Hash
        pose_model_sha256=(Get-FileHash $model -Algorithm SHA256).Hash
    } | ConvertTo-Json -Depth 3
    [IO.File]::WriteAllText((Join-Path $fixture 'release-manifest.json'), $metadata, (New-Object System.Text.UTF8Encoding($false)))
    $prefix = [IO.Path]::GetFullPath($fixture).TrimEnd('\', '/') + '\'
    $entries = @(Get-ChildItem -LiteralPath $fixture -File -Recurse | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            path=$_.FullName.Substring($prefix.Length).Replace('\', '/')
            bytes=$_.Length
            sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    })
    $rootManifest = [ordered]@{
        schema=1;kind='KilosGrammarWindowsRelease';engine='4.7.2.stable.official.TEST-FIXTURE'
        platform='win_amd64';files=$entries
    } | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $fixture 'manifest.json'), $rootManifest, (New-Object System.Text.UTF8Encoding($false)))
    & (Join-Path $fixture 'Test-ReleasePackage.ps1') -PackageRoot $fixture
    Write-Host 'PASS synthetic release manifest validates all existing bytes'
    Add-Content -LiteralPath $model -Value 'tamper'
    $caught = $false
    try { & (Join-Path $fixture 'Test-ReleasePackage.ps1') -PackageRoot $fixture } catch { $caught = $true }
    if (-not $caught) { throw 'Tampered release model passed the finished-release verifier.' }
    Write-Host 'PASS finished-release checker rejects modified files'
} finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
