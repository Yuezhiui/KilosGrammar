# Actual package-copy and read-only launch / safe-uninstall rehearsal in a
# unique, per-user directory with spaces. Never opens camera, API, DB or game.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PackageRoot)
$ErrorActionPreference='Stop'
$release = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$tag = [Guid]::NewGuid().ToString('N')
$destination = Join-Path (Join-Path $env:LOCALAPPDATA 'Programs') "Kilos Grammar Release QA $tag"
$testData = Join-Path $env:LOCALAPPDATA "KilosGrammar-Release-QA-Data-$tag"
if (Test-Path -LiteralPath $destination) { throw 'Fixture destination already exists.' }
if (Test-Path -LiteralPath $testData) { throw 'Fixture userdata already exists.' }
New-Item -ItemType Directory -Path $testData -Force | Out-Null
$sentinel = Join-Path $testData 'do-not-delete-my-data.txt'
[IO.File]::WriteAllText($sentinel,'EXTERNAL USER DATA MUST SURVIVE')
$installed = $false
try {
    $source = [IO.Path]::GetFullPath($PackageRoot)
    & (Join-Path $release 'Install-Portable.ps1') -PackageRoot $source -Destination $destination -AllowPreview -Simulate
    if (Test-Path -LiteralPath $destination) { throw 'Simulation wrote install directory.' }
    $denied = $false
    try {
        & (Join-Path $release 'Install-Portable.ps1') -PackageRoot $source `
            -Destination (Join-Path $env:ProgramFiles 'KilosGrammar-Unsafe-TestOnly') -AllowPreview -Simulate
    } catch { $denied=$true }
    if (-not $denied) { throw 'Installer accepted a Program Files destination.' }
    $denied = $false
    try { & (Join-Path $release 'Install-Portable.ps1') -PackageRoot $source -Destination $destination -Simulate } catch { $denied=$true }
    if (-not $denied) { throw 'Incomplete preview was accepted without explicit AllowPreview.' }
    & (Join-Path $release 'Install-Portable.ps1') -PackageRoot $source -Destination $destination -AllowPreview
    $installed = $true
    if (-not (Test-Path -LiteralPath (Join-Path $destination '.kilos-install.json') -PathType Leaf)) {
        throw 'Installer ownership journal absent.'
    }
    & (Join-Path $destination 'Test-LaunchPreflight.ps1') -PackageRoot $destination
    $denied = $false
    try {
        & (Join-Path $destination 'Test-LaunchPreflight.ps1') -PackageRoot $destination -RequireOfflineRuntime
    } catch { $denied=$true }
    if (-not $denied) { throw 'Incomplete preview was incorrectly certified with an offline Python runtime.' }
    $exe = Join-Path $destination 'KilosGrammar.exe'
    if (-not ((Get-Item -LiteralPath $exe).VersionInfo.ProductVersion -like '4.7.2.stable*')) {
        throw 'Installed developer preview does not contain the intended Godot 4.7.2 EXE.'
    }
    $denied = $false
    try { & (Join-Path $release 'Install-Portable.ps1') -PackageRoot $source -Destination $destination -AllowPreview -Simulate } catch { $denied=$true }
    if (-not $denied) { throw 'Installer allowed overwriting an existing install.' }
    $extra = Join-Path $destination 'UNKNOWN-USER-NOTES.txt'
    [IO.File]::WriteAllText($extra,'Must refuse to delete this file')
    $denied = $false
    try { & (Join-Path $destination 'Uninstall-Portable.ps1') -Destination $destination -Simulate } catch { $denied=$true }
    if (-not $denied -or -not (Test-Path $extra)) { throw 'Uninstall failed to protect unknown user file.' }
    # Remove only the uniquely named file this test created; never broadly
    # wipe user content or a development database.
    Remove-Item -LiteralPath $extra
    & (Join-Path $destination 'Uninstall-Portable.ps1') -Destination $destination -Simulate
    if (-not (Test-Path -LiteralPath $destination)) { throw 'Uninstall simulation deleted actual installation.' }
    & (Join-Path $destination 'Uninstall-Portable.ps1') -Destination $destination
    $installed=$false
    if (Test-Path -LiteralPath $destination) { throw 'Portable installed directory survived requested uninstall.' }
    if ((Get-Content -LiteralPath $sentinel -Raw) -ne 'EXTERNAL USER DATA MUST SURVIVE') {
        throw 'Uninstall altered external user data.'
    }
    Write-Host 'PASS per-user spaced-path: install simulation, actual copied EXE/PCK, read-only launch preflight, overwrite refusal, unknown-file refusal, safe uninstall, external user data preserved.'
} finally {
    if ($installed) {
        Write-Warning "Installation preserved for manual review after failure: $destination"
    }
    # Only this invocation's unique sentinel directory can be cleaned up.
    if (Test-Path -LiteralPath $testData) { Remove-Item -LiteralPath $testData -Recurse -Force }
}
