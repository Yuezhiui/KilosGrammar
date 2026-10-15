#requires -Version 5.1
<#
.SYNOPSIS
    Play Catch the Word in its own fullscreen Godot window.
.EXAMPLE
    .\tools\run_catch_fullscreen.ps1
.EXAMPLE
    .\tools\run_catch_fullscreen.ps1 -Character Grandma -Topic Adverb -Map Forest -Mode Lives -Difficulty Normal
.EXAMPLE
    .\tools\run_catch_fullscreen.ps1 -DryRun
.EXAMPLE
    .\tools\run_catch_fullscreen.ps1 -SmokeTest
.NOTES
    Run from PowerShell in any folder. Close the game window to stop Godot.
    This only runs Catch the Word; it does not change the project's main scene.
    In the Godot editor, Editor > Editor Settings > Run > Window Placement,
    disable "Embed Game on Next Play" (top-right game preview toolbar) if it is
    enabled, to run other project scenes outside the editor as well.
#>
[CmdletBinding()]
param(
    [ValidateSet('Boy', 'Girl', 'Grandma', 'Grandpa')]
    [string]$Character = 'Boy',
    [ValidateSet('Noun', 'Pronoun', 'Verb', 'Adjective', 'Adverb')]
    [string]$Topic = 'Noun',
    [ValidateSet('City', 'Forest', 'Mountain')]
    [string]$Map = 'City',
    [ValidateSet('Seconds', 'Lives')]
    [string]$Mode = 'Seconds',
    [ValidateSet('Easy', 'Normal', 'Hard')]
    [string]$Difficulty = 'Easy',
    [string]$GodotExecutable,
    [switch]$DryRun,
    [switch]$SmokeTest
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$previewScript = Join-Path $PSScriptRoot 'preview_catch_fullscreen.gd'
if (-not (Test-Path -LiteralPath $previewScript -PathType Leaf)) {
    throw "Missing preview script: $previewScript"
}
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'ui\minigames\catch_word.tscn') -PathType Leaf)) {
    throw "Catch the Word scene is missing from: $projectRoot"
}

$installedExe = Join-Path $env:USERPROFILE 'Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64.exe'
$installedConsole = Join-Path $env:USERPROFILE 'Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe'
$choices = @()
if (-not [string]::IsNullOrWhiteSpace($GodotExecutable)) {
    $choices += $GodotExecutable
} else {
    if ($SmokeTest) { $choices += $installedConsole }
    $choices += $installedExe
    $choices += $installedConsole
    foreach ($name in @('godot', 'godot4')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $command) { $choices += $command.Source }
    }
}

$engine = $null
foreach ($candidate in $choices) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $engine = (Resolve-Path -LiteralPath $candidate).Path
        break
    }
}
if ($null -eq $engine) {
    throw 'Godot 4.7 was not found. Use -GodotExecutable "C:\path\to\Godot_v4.7.2-stable_win64.exe".'
}

$arguments = @('--path', $projectRoot)
if ($SmokeTest) {
    $arguments += '--headless'
} else {
    $arguments += '--fullscreen'
}
$arguments += @(
    '--rendering-method', 'gl_compatibility',
    '--script', 'res://tools/preview_catch_fullscreen.gd',
    '--',
    "--character=$Character", "--topic=$Topic", "--map=$Map",
    "--mode=$Mode", "--difficulty=$Difficulty"
)
if ($SmokeTest) { $arguments += '--smoke-test' }

$display = @($engine) + $arguments | ForEach-Object {
    if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
}
Write-Host ('Godot command: ' + ($display -join ' '))
if ($DryRun) {
    Write-Host 'Dry run: no Godot process started.'
    return
}

# Keep the graphical game in its own interactive window, while waiting for it
# to exit. Keep smoke tests in this console so their PASS/FAIL log is visible.
if ($SmokeTest) {
    & $engine @arguments
    $godotExit = $LASTEXITCODE
} else {
    $windowsArguments = @($arguments | ForEach-Object {
        if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
    })
    $gameProcess = Start-Process -FilePath $engine -ArgumentList $windowsArguments -PassThru -Wait
    $godotExit = $gameProcess.ExitCode
}
if ($godotExit -ne 0) {
    throw "Godot fullscreen preview exited with code $godotExit"
}
