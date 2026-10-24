# Run manually from the repository root:
#   .\database\run_local.ps1           # Start only; never auto-migrate
#   .\database\run_local.ps1 -Migrate  # Explicitly create tables after backup/review
param(
    [switch]$Migrate,
    [string]$DbName = 'kilos_grammar',
    [string]$DbUser = 'kilos_app',
    [int]$DbPort = 5432,
    [int]$HttpPort = 18765
)

$ErrorActionPreference = 'Stop'
$virtualPython = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $virtualPython)) {
    throw 'Missing virtual environment. Run .\database\setup_local.ps1 first.'
}

$env:KILOS_DB_HOST = '127.0.0.1'
$env:KILOS_DB_NAME = $DbName
$env:KILOS_DB_USER = $DbUser
$env:KILOS_DB_PORT = [string]$DbPort
$env:KILOS_HTTP_PORT = [string]$HttpPort

# Password is prompted without echo and is never written to files or command history.
$password = Read-Host 'Local PostgreSQL password' -AsSecureString
$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
try {
    $env:KILOS_DB_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    Push-Location (Split-Path -Parent $PSScriptRoot)
    try {
        $originalPreference = $ErrorActionPreference
        try {
            # Native Python can write diagnostic text to stderr on Windows.
            # Keep it visible and use its exit code to detect real failure.
            $ErrorActionPreference = 'Continue'
            if ($Migrate) {
                & $virtualPython -m database.migrate --apply
            } else {
                & $virtualPython -m database.server
            }
            $processExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $originalPreference
        }
        if ($processExitCode -ne 0) { throw 'Database command failed; verify localhost credentials, database, and schema.' }
    } finally {
        Pop-Location
    }
} finally {
    Remove-Item Env:KILOS_DB_PASSWORD -ErrorAction SilentlyContinue
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
}
