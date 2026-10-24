# Synthetic read-only-validation fixture; all created files stay within this
# packaging subtree and are removed by this test's own finally block.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$releaseRoot = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $releaseRoot 'staging\payload-integrity-test'
if (Test-Path -LiteralPath $fixture) { throw 'Refusing to overwrite existing release test fixture.' }
$offline = Join-Path $fixture 'offline'
New-Item -ItemType Directory -Force -Path $offline | Out-Null
try {
    $relativeFiles = @(
        'models/yolo26n-pose.pt',
        'installers/python-3.11.9-amd64.exe',
        'installers/postgresql-18.0-1-windows-x64.exe',
        'wheels/psycopg-3.3.6-py3-none-any.whl',
        'wheels/psycopg_binary-3.3.6-cp311-cp311-win_amd64.whl',
        'wheels/ultralytics-8.4.142-py3-none-any.whl',
        'wheels/torch-2.6.0-cp311-cp311-win_amd64.whl',
        'wheels/torchvision-0.21.0-cp311-cp311-win_amd64.whl',
        'wheels/opencv_python-5.0.0.93-cp311-cp311-win_amd64.whl',
        'wheels/lap-0.5.13-cp311-cp311-win_amd64.whl'
    )
    $inventory = @()
    foreach ($relative in $relativeFiles) {
        $path = Join-Path $offline $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
        [IO.File]::WriteAllText($path, 'fixture-content:' + $relative)
        $inventory += @{path=$relative;bytes=(Get-Item $path).Length;sha256=(Get-FileHash $path -Algorithm SHA256).Hash}
    }
    @{schema=1;python='3.11';platform='win_amd64';files=$inventory} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $offline 'manifest.json') -Encoding UTF8
    & (Join-Path $releaseRoot 'Test-OfflinePayload.ps1') -PayloadRoot $fixture -Quiet
    Write-Host 'PASS synthetic valid manifest'
    Add-Content -LiteralPath (Join-Path $offline 'wheels\lap-0.5.13-cp311-cp311-win_amd64.whl') -Value 'tamper'
    $caught = $false
    try { & (Join-Path $releaseRoot 'Test-OfflinePayload.ps1') -PayloadRoot $fixture -Quiet } catch { $caught = $true }
    if (-not $caught) { throw 'Tamper detection regression: corrupted wheel passed checks.' }
    Write-Host 'PASS corrupted wheel correctly rejected'
    $inventory[0].path = '../outside.txt'
    @{schema=1;python='3.11';platform='win_amd64';files=$inventory} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $offline 'manifest.json') -Encoding UTF8
    $caught = $false
    try { & (Join-Path $releaseRoot 'Test-OfflinePayload.ps1') -PayloadRoot $fixture -Quiet } catch { $caught = $true }
    if (-not $caught) { throw 'Path traversal regression: parent path passed checks.' }
    Write-Host 'PASS traversal rejected'
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
