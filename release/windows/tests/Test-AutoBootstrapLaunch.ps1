# Isolated launcher regression: never invokes a real game, service, installer,
# PostgreSQL, database or webcam. All runtime files are synthetic test data.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$release = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $env:TEMP ('KilosGrammar-AutoBootstrap-QA-' + [guid]::NewGuid().ToString('N'))
$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
$previousPython = $env:KILOSGRAMMAR_PYTHON
$checks = 0
function Assert([bool]$condition, [string]$label) {
    if (-not $condition) { throw "FAIL auto-bootstrap: $label" }
    $script:checks++
}
try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $env:APPDATA = Join-Path $scratch 'Roaming'
    $env:LOCALAPPDATA = Join-Path $scratch 'Local'
    $package = Join-Path $scratch 'School Install With Spaces'
    foreach ($part in @('offline\models','database\.venv\Scripts','offline\installers')) {
        New-Item -ItemType Directory -Path (Join-Path $package $part) -Force | Out-Null
    }
    foreach ($name in @('Launch-Game.ps1','Install-OnSchoolPC.ps1')) {
        Copy-Item -LiteralPath (Join-Path $release $name) -Destination (Join-Path $package $name)
    }
    # These placeholders are deliberately NOT executable. A real game could
    # only start if the test's mocked Start-Process were bypassed.
    foreach ($name in @('KilosGrammar.exe','KilosGrammar.pck',
                         'database\.venv\Scripts\python.exe')) {
        Set-Content -LiteralPath (Join-Path $package $name) -Value 'QA placeholder' -Encoding ASCII
    }
    $offlineManifest = Join-Path $package 'offline\manifest.json'
    Set-Content -LiteralPath $offlineManifest -Value '{"qa":"no real installers"}' -Encoding ASCII
    $pose = Join-Path $package 'offline\models\yolo26n-pose.pt'
    Set-Content -LiteralPath $pose -Value 'QA pose' -Encoding ASCII
    $marker = Join-Path $package 'database\.venv\kilos-offline-manifest.sha256'
    $hash = (Get-FileHash -LiteralPath $offlineManifest -Algorithm SHA256).Hash
    Set-Content -LiteralPath $marker -Value $hash -Encoding ASCII
    $modelDest = Join-Path $env:APPDATA 'Godot\app_userdata\KilosGrammar\pose_models\yolo26n-pose.pt'
    New-Item -ItemType Directory -Path (Split-Path -Parent $modelDest) -Force | Out-Null
    Copy-Item -LiteralPath $pose -Destination $modelDest
    # CheckOnly must dispatch only the dry-run QA interface and return.
    Set-Content -LiteralPath (Join-Path $package 'Test-LaunchPreflight.ps1') -Value @'
param([string]$PackageRoot,[switch]$RequireOfflineRuntime)
if (-not $RequireOfflineRuntime) { throw 'Required dry-run flag missing' }
$global:kgBootstrapTestPreflight = $true
'@ -Encoding UTF8
    $global:kgBootstrapTestLaunches = 0
    $global:kgBootstrapTestStarts = 0
    $global:kgBootstrapTestState = 'Running'
    $global:kgBootstrapTestPreflight = $false
    function Get-Service {
        [CmdletBinding()]
        param([string]$Name)
        if ($Name -ne 'postgresql-x64-18' -or $global:kgBootstrapTestState -eq 'Missing') { return $null }
        $service = [pscustomobject]@{ Status=$global:kgBootstrapTestState }
        $service | Add-Member ScriptMethod WaitForStatus {
            param($expected,$timeout)
            $this.Status='Running'
            $global:kgBootstrapTestState='Running'
        } -Force
        return $service
    }
    function Start-Service {
        [CmdletBinding()]
        param([string]$Name)
        if ($Name -ne 'postgresql-x64-18') { throw 'Unexpected service start' }
        $global:kgBootstrapTestStarts++
    }
    function Start-Process {
        [CmdletBinding()]
        param([string]$FilePath,[string]$WorkingDirectory)
        if ($FilePath -ne (Join-Path $package 'KilosGrammar.exe')) {
            throw "Unexpected process start: $FilePath"
        }
        Assert ($env:KILOSGRAMMAR_PYTHON -eq (Join-Path $package 'database\.venv\Scripts\python.exe')) 'child inherited offline Python'
        $global:kgBootstrapTestLaunches++
    }
    & (Join-Path $package 'Launch-Game.ps1') -CheckOnly
    Assert $global:kgBootstrapTestPreflight 'CheckOnly forwarded dry-run'
    Assert ($global:kgBootstrapTestLaunches -eq 0) 'CheckOnly launched no game'
    Assert ($global:kgBootstrapTestStarts -eq 0) 'CheckOnly started no service'

    & (Join-Path $package 'Launch-Game.ps1')
    Assert ($global:kgBootstrapTestLaunches -eq 1) 'verified local runtime launched'
    Assert ($global:kgBootstrapTestStarts -eq 0) 'running service was not restarted'
    Assert ([string]::IsNullOrEmpty($env:KILOSGRAMMAR_PYTHON)) 'parent Python environment restored'

    $global:kgBootstrapTestState='Stopped'
    & (Join-Path $package 'Launch-Game.ps1')
    Assert ($global:kgBootstrapTestLaunches -eq 2) 'stopped service resumed then game launched'
    Assert ($global:kgBootstrapTestStarts -eq 1) 'only installed standard service started once'
    $global:kgBootstrapTestState='Missing'
    $blocked = $false
    try { & (Join-Path $package 'Launch-Game.ps1') } catch {
        $blocked = ($_.Exception.Message -match 'PostgreSQL 18 is not installed')
    }
    Assert $blocked 'missing PostgreSQL gives explicit admin guidance'
    Assert ($global:kgBootstrapTestLaunches -eq 2) 'missing service did not launch game'
    Assert ($global:kgBootstrapTestStarts -eq 1) 'missing service did not invoke installer'

    # Check source installer separates a per-user Python-only bootstrap from
    # the independent PostgreSQL administrator-controlled setup.
    $installSource = Get-Content -LiteralPath (Join-Path $package 'Install-OnSchoolPC.ps1') -Raw
    Assert ($installSource.Contains('if (-not $PythonOnly)')) 'PythonOnly bypasses PostgreSQL'
    Assert ($installSource.Contains('Get-AuthenticodeSignature')) 'automatic Python installer signature checked'
    Assert ($installSource.Contains("InstallAllUsers=0")) 'automatic Python install is per-user'
    Assert ($installSource.Contains('Test-OfflinePayload.ps1')) 'offline manifest checked before Python install'
    Assert (-not ($installSource -match '(?i)Invoke-WebRequest|Start-Process\s+-FilePath\s+\$pgInstaller')) 'no network or PostgreSQL installer execution'

    Write-Host "PASS auto-bootstrap isolated launch QA: $checks checks; no DB, installer, real service, or game executed."
} finally {
    foreach ($name in @('kgBootstrapTestLaunches','kgBootstrapTestStarts','kgBootstrapTestState','kgBootstrapTestPreflight')) {
        Remove-Variable -Scope Global -Name $name -ErrorAction SilentlyContinue
    }
    $env:APPDATA = $previousAppData
    $env:LOCALAPPDATA = $previousLocalAppData
    if ($null -eq $previousPython) { Remove-Item Env:KILOSGRAMMAR_PYTHON -ErrorAction SilentlyContinue }
    else { $env:KILOSGRAMMAR_PYTHON = $previousPython }
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
