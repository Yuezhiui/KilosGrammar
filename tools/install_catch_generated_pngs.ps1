<#
    Installs ONLY the nine separately generated reference PNGs for
    Catch the Word, without modifying the other character/map assets.

    Usage from project root:
      powershell -ExecutionPolicy Bypass -File tools/install_catch_generated_pngs.ps1

    The default archive is in the Windows Downloads folder after clicking
    the ChatGPT link for KilosGrammar_Catch_Actual_Generated_PNGs.zip.
    Alternatively pass -ArchivePath 'C:\path\to\archive.zip'.
#>
param(
    [string] $ArchivePath = '',
    [switch] $SkipGodotImport
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$relativeFolder = 'ui/minigames/catch_the_word/catch_hud/generated/'
$images = @(
    'title_board.png', 'objective_banner.png', 'lives_badge.png',
    'timer_badge.png', 'pause_badge.png', 'score_board.png',
    'character/boy_body.png', 'character/boy_basket_hands.png',
    'character/word_apple.png'
)

if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $ArchivePath = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\KilosGrammar_Catch_Actual_Generated_PNGs.zip'
}
$ArchivePath = [System.IO.Path]::GetFullPath($ArchivePath)
if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
    throw "PNG archive was not found at $ArchivePath. Download the referenced ZIP to Downloads first, then run this script."
}

Add-Type -AssemblyName System.IO.Compression
$archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
try {
    # Verify that ALL required PNGs are present before touching existing files.
    $sources = @{}
    foreach ($asset in $images) {
        $zipPath = ($relativeFolder + $asset).Replace('\', '/')
        $entry = $archive.Entries | Where-Object { $_.FullName.Replace('\', '/') -eq $zipPath } | Select-Object -First 1
        if ($null -eq $entry) {
            throw "Missing $zipPath in PNG archive. Nothing has been installed."
        }
        $sources[$asset] = $entry
    }

    foreach ($asset in $images) {
        $destination = [System.IO.Path]::GetFullPath((Join-Path $projectRoot ($relativeFolder + $asset)))
        if (-not $destination.StartsWith($projectRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to install outside project: $destination"
        }
        $folder = [System.IO.Path]::GetDirectoryName($destination)
        [System.IO.Directory]::CreateDirectory($folder) | Out-Null
        $temp = $destination + '.installing'
        $inputStream = $sources[$asset].Open()
        try {
            $outputStream = [System.IO.File]::Create($temp)
            try { $inputStream.CopyTo($outputStream) }
            finally { $outputStream.Dispose() }
        }
        finally { $inputStream.Dispose() }
        $stream = [System.IO.File]::OpenRead($temp)
        try {
            $signature = New-Object byte[] 8
            if ($stream.Read($signature, 0, 8) -ne 8 -or
                [BitConverter]::ToString($signature) -ne '89-50-4E-47-0D-0A-1A-0A') {
                throw "Not a valid PNG: $asset"
            }
        }
        finally { $stream.Dispose() }
        Move-Item -LiteralPath $temp -Destination $destination -Force
        Write-Host ('Installed ' + $asset)
    }
}
finally {
    $archive.Dispose()
}

if (-not $SkipGodotImport) {
    $godotConsole = Join-Path $env:USERPROFILE 'Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe'
    if (-not (Test-Path -LiteralPath $godotConsole)) {
        $foundGodot = Get-Command godot -ErrorAction SilentlyContinue
        if ($foundGodot) { $godotConsole = $foundGodot.Source }
    }
    if (Test-Path -LiteralPath $godotConsole) {
        & $godotConsole --headless --editor --path $projectRoot --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import failed with exit code $LASTEXITCODE" }
        Write-Host 'Godot imported the new images.'
    }
    else {
        Write-Warning 'No Godot console executable at the known location. Open the project in Godot to import the PNGs.'
    }
}
Write-Host 'Catch the Word PNG installation completed successfully.'
