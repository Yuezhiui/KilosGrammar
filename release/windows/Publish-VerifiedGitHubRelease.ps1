# Draft a release with ordinary authenticated GitHub CLI. Never reads tokens.
# This is intentionally guarded by explicit evidence of required release gates.
[CmdletBinding()]
param(
    [switch]$ApproveRedistributionRights,
    [switch]$ApproveCleanOfflineLaptopAcceptance,
    [string]$NotesFile = '',
    [string]$Repository = 'Yuezhiui/KilosGrammar'
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$version = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
if ($version -cnotmatch '^\d+\.\d+\.\d+-beta\.\d+$') { throw 'Invalid source version.' }
$tag = 'v' + $version
if (-not $ApproveRedistributionRights -or -not $ApproveCleanOfflineLaptopAcceptance) {
    throw 'Release blocked until redistribution rights and offline clean-laptop testing are verified. Never provide these switches without evidence.'
}
$package = Join-Path $PSScriptRoot ('out\KilosGrammar-win-x64-' + $tag)
$zip = Join-Path $PSScriptRoot ('out\KilosGrammar-' + $tag + '-OFFLINE-CANDIDATE-NOT-CLEAN-PC-TESTED-win-x64.zip')
$setup = Join-Path $PSScriptRoot ('out\KilosGrammar-' + $tag + '-OFFLINE-CANDIDATE-NOT-CLEAN-PC-TESTED-Setup.exe')
& (Join-Path $PSScriptRoot 'Test-ReleasePackage.ps1') -PackageRoot $package
& (Join-Path $PSScriptRoot 'Test-VerifiedOfflineZip.ps1') -ZipPath $zip -PackageRoot $package
$assets = @($zip, "$zip.sha256.txt", $setup, "$setup.sha256.txt", (Join-Path $package 'KilosGrammar.exe'), (Join-Path $package 'KilosGrammar.pck'))
foreach ($path in $assets) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing release asset: $path" }
}
foreach ($path in @($zip, $setup)) {
    $expected = ((Get-Content -LiteralPath "$path.sha256.txt" -Raw).Trim() -split '\s+')[0].ToUpperInvariant()
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected) { throw "Checksum mismatch: $path" }
}
if (-not $NotesFile) { $NotesFile = Join-Path $PSScriptRoot ('RELEASE-NOTES-' + $tag + '.md') }
if (-not (Test-Path -LiteralPath $NotesFile -PathType Leaf)) { throw "Release notes missing: $NotesFile" }
$cli = Get-Command gh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $cli) { throw 'Official GitHub CLI missing. Install gh.exe and authenticate using gh auth login; no token extraction.' }
& $cli.Source auth status
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI unauthenticated; use the supported gh auth login flow.' }
& $cli.Source release view $tag --repo $Repository *> $null
if ($LASTEXITCODE -eq 0) { throw "Release already exists: $tag. Refusing overwrite." }
& $cli.Source release create $tag @assets --repo $Repository --verify-tag --draft --prerelease --title ("KilosGrammar " + $tag + " Offline Windows beta") --notes-file $NotesFile
if ($LASTEXITCODE -ne 0) { throw 'Release upload did not finish. Inspect the GitHub draft state before retrying.' }
Write-Host "DRAFT release created for $tag with checked assets; publishing requires final reviewer approval."
