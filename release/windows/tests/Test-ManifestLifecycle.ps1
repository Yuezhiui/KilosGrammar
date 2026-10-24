# Simulated local staging only. Test data are unmistakably fake text fixtures,
# kept under release/windows/staging and removed in finally.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$release = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $release ('staging\manifest-qa-' + [Guid]::NewGuid().ToString('N'))
$sandbox = Join-Path $fixture 'sandbox'
$wheels = Join-Path $fixture 'inputs\wheels'
if (Test-Path -LiteralPath $fixture) { throw 'Refusing to reuse a release QA fixture.' }
try {
    New-Item -ItemType Directory -Path $sandbox,$wheels -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $release 'Stage-OfflinePrerequisites.ps1') -Destination (Join-Path $sandbox 'Stage-OfflinePrerequisites.ps1')
    Copy-Item -LiteralPath (Join-Path $release 'Test-OfflinePayload.ps1') -Destination (Join-Path $sandbox 'Test-OfflinePayload.ps1')
    $model = Join-Path $fixture 'inputs\yolo26n-pose.pt'
    $python = Join-Path $fixture 'inputs\python-3.11.9-amd64.exe'
    $postgres = Join-Path $fixture 'inputs\postgresql-18.0-1-windows-x64.exe'
    foreach ($source in @($model,$python,$postgres)) {
        [IO.File]::WriteAllText($source, 'QA fixture, not installable: ' + $source)
    }
    $wheelNames = @(
        'psycopg-3.3.6-py3-none-any.whl', 'psycopg_binary-3.3.6-cp311-cp311-win_amd64.whl',
        'ultralytics-8.4.142-py3-none-any.whl', 'torch-2.6.0-cp311-cp311-win_amd64.whl',
        'torchvision-0.21.0-cp311-cp311-win_amd64.whl',
        'opencv_python-5.0.0.93-cp311-cp311-win_amd64.whl',
        'lap-0.5.13-cp311-cp311-win_amd64.whl'
    )
    foreach ($name in $wheelNames) { [IO.File]::WriteAllText((Join-Path $wheels $name), 'QA fixture, not a wheel: ' + $name) }
    $script = Join-Path $sandbox 'Stage-OfflinePrerequisites.ps1'
    $absentModel = Join-Path $fixture 'inputs\missing.pt'
    $caught = $false
    try { & $script -ModelPath $absentModel -PythonInstallerPath $python -PostgreSqlInstallerPath $postgres -WheelhouseDirectory $wheels } catch { $caught = $true }
    if (-not $caught -or (Test-Path -LiteralPath (Join-Path $sandbox 'offline'))) {
        throw 'Missing artifact created a misleading offline payload or passed preflight.'
    }
    Write-Host 'PASS incomplete inputs refused before manifest creation'

    & $script -ModelPath $model -PythonInstallerPath $python -PostgreSqlInstallerPath $postgres -WheelhouseDirectory $wheels
    $manifest = Join-Path $sandbox 'offline\manifest.json'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'Successful synthetic staging did not publish its input manifest.' }
    & (Join-Path $sandbox 'Test-OfflinePayload.ps1') -PayloadRoot $sandbox -Quiet
    Write-Host 'PASS complete synthetic fixture created an accurate manifest'

    $before = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
    $caught = $false
    try { & $script -ModelPath $model -PythonInstallerPath $python -PostgreSqlInstallerPath $postgres -WheelhouseDirectory $wheels } catch { $caught = $true }
    if (-not $caught -or (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash -ne $before) {
        throw 'Repeated staging unexpectedly overwrote a validated manifest.'
    }
    Write-Host 'PASS existing staged inputs are preserved'

    Add-Content -LiteralPath (Join-Path $sandbox 'offline\wheels\lap-0.5.13-cp311-cp311-win_amd64.whl') -Value 'tamper'
    $caught = $false
    try { & (Join-Path $sandbox 'Test-OfflinePayload.ps1') -PayloadRoot $sandbox -Quiet } catch { $caught = $true }
    if (-not $caught) { throw 'Corrupt input passed manifest integrity verification.' }
    Write-Host 'PASS tampered staged input rejected'

    $caught = $false
    try { & (Join-Path $release 'Test-ReleasePackage.ps1') -PackageRoot (Join-Path $fixture 'nonexistent-export') } catch { $caught = $true }
    if (-not $caught -or (Test-Path -LiteralPath (Join-Path $fixture 'nonexistent-export'))) {
        throw 'Absent EXE/PCK release unexpectedly received a fabricated root manifest.'
    }
    Write-Host 'PASS absent exported release never receives a fabricated manifest'
} finally {
    # The fixture name was generated in this invocation and was absent above.
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
