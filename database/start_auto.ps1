# Starts the local PostgreSQL HTTP service with per-user encrypted credentials.
# Safe to invoke before each Godot launch: exits quickly if the service is ready.
# No Read-Host, migrations, PostgreSQL auth changes, global dependency installs,
# password command-line args, secret logs, or cloud/network calls.
param(
    [int]$HttpPort = 18765
)

$ErrorActionPreference = 'Stop'
$virtualPython = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$credentialDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'KilosGrammar'
$credentialPath = Join-Path $credentialDir 'db_credentials.xml'
$healthUrl = "http://127.0.0.1:$HttpPort/health"

function Test-LocalListener([int]$port) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect('127.0.0.1', $port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(300)) { return $false }
        $client.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Test-DatabaseReady {
    try {
        $reply = Invoke-RestMethod -Method Get -Uri $healthUrl -TimeoutSec 2
        return ($null -ne $reply -and $reply.ok -eq $true -and
                $reply.data.status -eq 'ok' -and $reply.data.database -eq 'connected')
    } catch {
        return $false
    }
}

if ($HttpPort -lt 1 -or $HttpPort -gt 65535) {
    Write-Error 'HttpPort must be 1-65535.'
    exit 1
}

# Port availability and readiness are checked before touching credentials;
# this avoids creating duplicate Python processes when Godot opens twice.
if (Test-LocalListener $HttpPort) {
    if (Test-DatabaseReady) {
        Write-Host "Local PostgreSQL API already ready at $healthUrl"
        exit 0
    }
    Write-Warning "Something is listening at 127.0.0.1:$HttpPort, but the database health check failed. Check database credentials/schema and the existing process."
    exit 1
}

if (-not (Test-Path -LiteralPath $virtualPython -PathType Leaf)) {
    Write-Warning 'Python virtual environment missing. Run .\database\setup_local.ps1 once.'
    exit 1
}
if (-not (Test-Path -LiteralPath $credentialPath -PathType Leaf)) {
    Write-Warning 'No saved database credentials. Run .\database\configure_local.ps1 interactively once.'
    exit 1
}

$passwordPointer = [IntPtr]::Zero
$newProcess = $null
try {
    try {
        $saved = Import-Clixml -LiteralPath $credentialPath -ErrorAction Stop
    } catch {
        throw 'Cannot decrypt saved credentials with this Windows account. Run configure_local.ps1 again under the game user.'
    }
    if ($saved.Version -ne 1 -or $saved.Host -ne '127.0.0.1' -or
        -not ($saved.Password -is [Security.SecureString]) -or
        $saved.User -cnotmatch '^[a-z_][a-z0-9_]{0,62}$' -or
        $saved.Database -cnotmatch '^[a-z_][a-z0-9_]{0,62}$' -or
        [int]$saved.Port -lt 1 -or [int]$saved.Port -gt 65535) {
        throw 'Saved credential file has an unexpected format. Reconfigure locally.'
    }

    $env:KILOS_DB_HOST = '127.0.0.1'
    $env:KILOS_DB_PORT = [string]([int]$saved.Port)
    $env:KILOS_DB_NAME = [string]$saved.Database
    $env:KILOS_DB_USER = [string]$saved.User
    $env:KILOS_HTTP_PORT = [string]$HttpPort
    $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($saved.Password)
    $env:KILOS_DB_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)

    # Launch in its own hidden Windows process and exit after a short health
    # check. The secret is passed only as the child process environment, never
    # in command-line parameters or logs.
    $newProcess = Start-Process -FilePath $virtualPython -ArgumentList @('-m', 'database.server') `
        -WorkingDirectory $repositoryRoot -WindowStyle Hidden -PassThru
} catch {
    # Never expose the exception object: environment/credentials are private.
    Write-Warning 'Unable to start local PostgreSQL API. Verify saved credentials, Python venv, and port availability.'
    exit 1
} finally {
    Remove-Item Env:KILOS_DB_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:KILOS_DB_USER -ErrorAction SilentlyContinue
    Remove-Item Env:KILOS_DB_NAME -ErrorAction SilentlyContinue
    Remove-Item Env:KILOS_DB_HOST -ErrorAction SilentlyContinue
    Remove-Item Env:KILOS_DB_PORT -ErrorAction SilentlyContinue
    Remove-Item Env:KILOS_HTTP_PORT -ErrorAction SilentlyContinue
    if ($passwordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }
}

for ($attempt = 0; $attempt -lt 18; $attempt++) {
    if (Test-DatabaseReady) {
        Write-Host "Local PostgreSQL API ready at $healthUrl"
        exit 0
    }
    if ($newProcess.HasExited) { break }
    Start-Sleep -Milliseconds 300
}

# Only stop the process started by this invocation. Never terminate any
# unrelated process that happened to occupy the expected port.
if ($null -ne $newProcess -and -not $newProcess.HasExited) {
    Stop-Process -Id $newProcess.Id -Force -ErrorAction SilentlyContinue
}
Write-Warning 'API process started but database readiness failed. Re-run configure_local.ps1 to verify PostgreSQL login and schema.'
exit 1
