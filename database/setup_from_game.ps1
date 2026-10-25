# Godot's one-click first-run entrypoint. Call with:
#   powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<project>\database\setup_from_game.ps1"
# This short-lived noninteractive wrapper opens a SEPARATE VISIBLE PowerShell
# console for the one-time PostgreSQL password and confirmations. It never
# passes passwords on a command line or changes PostgreSQL automatically.
param(
    [switch]$InteractiveSession,
    [int]$HttpPort = 18765
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$setupScript = Join-Path $PSScriptRoot 'configure_local.ps1'
$autoScript = Join-Path $PSScriptRoot 'start_auto.ps1'
$upgradeScript = Join-Path $PSScriptRoot 'upgrade_existing_scores.ps1'
$venvPython = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
$credentialPath = Join-Path (
    [Environment]::GetFolderPath('LocalApplicationData')) 'KilosGrammar\db_credentials.xml'
$healthUrl = "http://127.0.0.1:$HttpPort/health"
$windowsShell = Join-Path $PSHOME 'powershell.exe'
$accountSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value.Replace('-', '_')
$wizardMutexName = 'Local\KilosGrammarDbWizard_' + $accountSid
$launchMutexName = 'Local\KilosGrammarDbWizardLaunch_' + $accountSid

function Test-Ready {
    try {
        $response = Invoke-RestMethod -Method Get -Uri $healthUrl -TimeoutSec 2
        return ($response.ok -eq $true -and $response.data.status -eq 'ok' -and
                $response.data.database -eq 'connected')
    } catch {
        return $false
    }
}

function Test-WizardAlreadyOpen {
    $existing = $null
    try {
        $existing = [Threading.Mutex]::OpenExisting($wizardMutexName)
        try {
            if ($existing.WaitOne(0)) {
                $existing.ReleaseMutex()
                return $false
            }
            return $true
        } catch [Threading.AbandonedMutexException] {
            $existing.ReleaseMutex()
            return $false
        }
    } catch [Threading.WaitHandleCannotBeOpenedException] {
        return $false
    } finally {
        if ($null -ne $existing) { $existing.Dispose() }
    }
}

if ($HttpPort -lt 1 -or $HttpPort -gt 65535) {
    Write-Warning 'Invalid localhost API port.'
    exit 1
}

if ($InteractiveSession) {
    # Held for the duration of the wizard. Repeated Godot launches reuse the
    # existing interactive window instead of opening duplicate password forms.
    $createdNew = $false
    $wizardMutex = New-Object System.Threading.Mutex($true, $wizardMutexName, [ref]$createdNew)
    $ownsMutex = $createdNew
    if (-not $ownsMutex) {
        try {
            $ownsMutex = $wizardMutex.WaitOne(0)
        } catch [Threading.AbandonedMutexException] {
            $ownsMutex = $true
        }
    }
    if (-not $ownsMutex) {
        Write-Host 'KILOS GRAMMAR database setup is already open in another window.'
        $wizardMutex.Dispose()
        return
    }

    try {
        Write-Host ''
        Write-Host 'KILOS GRAMMAR - FIRST-TIME LOCAL DATABASE SETUP'
        Write-Host 'The game opened this window to configure the local PostgreSQL database.'
        Write-Host 'Enter the local PostgreSQL account details when prompted.'
        Write-Host 'Passwords are hidden; app credentials are protected with Windows DPAPI.'
        Write-Host 'Only explicitly confirmed CREATE or MIGRATE actions change the database.'
        Write-Host ''

        if (Test-Ready) {
            Write-Host 'Local PostgreSQL is already online. You can return to the game.'
            return
        }

        if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
            Write-Warning 'Local Python runtime is not installed in database/.venv.'
            Write-Host 'KILOS GRAMMAR requires its packaged Python environment and PostgreSQL driver.'
            Write-Host 'The wizard will not download dependencies or install packages globally.'
            return
        }

        $requestedMode = 'LOGIN'
        if (-not (Test-Path -LiteralPath $credentialPath -PathType Leaf)) {
            Write-Host 'No application database credentials have been saved on this Windows account.'
            Write-Host '1 - I already have a PostgreSQL application username and password'
            Write-Host '2 - Create a NEW local application role/database with a generated strong password'
            Write-Host '3 - Recover the app password of a newly created EMPTY database (after interrupted setup)'
            Write-Host 'Q - Set up later'
            $initialChoice = Read-Host 'Choose 1, 2, 3, or Q'
            switch ($initialChoice.Trim().ToUpperInvariant()) {
                '1' { $requestedMode = 'LOGIN' }
                '2' { $requestedMode = 'CREATE' }
                '3' { $requestedMode = 'REPAIR' }
                'Q' { Write-Host 'Setup cancelled. The game will offer setup again while the database is offline.'; return }
                default { Write-Host 'Existing PostgreSQL account login selected.'; $requestedMode = 'LOGIN' }
            }
        } else {
            Write-Host 'Encrypted credentials already exist. If scores appear missing after restart, the existing database may need a schema upgrade.'
            Write-Host '5 - Check and safely upgrade EXISTING scores (private backup + typed MIGRATE, never recreates database)'
            Write-Host 'Enter - Continue the usual local database login/setup'
            $existingChoice = Read-Host 'Choose 5 or press Enter'
            if ($existingChoice.Trim() -eq '5') { $requestedMode = 'UPGRADE' }
        }
        for ($attempt = 1; $attempt -le 6; $attempt++) {
            Write-Host ''
            if ($requestedMode -eq 'CREATE') {
                Write-Host 'New role/database setup uses a generated application password and requires your existing PostgreSQL administrator password.'
            } elseif ($requestedMode -eq 'REPAIR') {
                Write-Host 'Credential recovery verifies that the role owns a NEW EMPTY app database, then asks for explicit RESET and the existing PostgreSQL administrator password.'
            } elseif ($requestedMode -eq 'MIGRATE') {
                Write-Host 'Please review database/migrations/001_initial.sql before confirming schema creation.'
            } elseif ($requestedMode -eq 'UPGRADE') {
                Write-Host 'Preserve existing students and scores: backup/verify before the optional 002 migration.'
            }

            # This is an interactive console session. The configuration script
            # owns the app password and explicit confirmation prompts; none of
            # that data is passed from Godot or in process arguments.
            try {
                if ($requestedMode -eq 'CREATE') {
                    # A freshly created app role gets a securely generated
                    # password protected by DPAPI after the user confirms.
                    & $setupScript -InitializeNewDatabase -GenerateAppPassword
                } elseif ($requestedMode -eq 'REPAIR') {
                    & $setupScript -RepairNewAppCredentials -GenerateAppPassword
                } elseif ($requestedMode -eq 'MIGRATE') {
                    & $setupScript -Migrate
                } elseif ($requestedMode -eq 'UPGRADE') {
                    & $upgradeScript
                } else {
                    & $setupScript
                }
                $configurationExit = $LASTEXITCODE
                if ($null -eq $configurationExit) { $configurationExit = 1 }
            } catch {
                Write-Warning 'Local setup could not complete. Verify the Python environment and local PostgreSQL settings.'
                $configurationExit = 1
            }

            if ($configurationExit -eq 0) {
                Write-Host 'Configuration saved. Starting the localhost database service...'
                try {
                    & $autoScript -HttpPort $HttpPort
                    $startupExit = $LASTEXITCODE
                } catch {
                    $startupExit = 1
                }
                if ($startupExit -eq 0 -and (Test-Ready)) {
                    Write-Host 'LOCAL POSTGRESQL ONLINE. Return to KILOS GRAMMAR.'
                    return
                }
                Write-Warning 'Credentials were saved, but the API health check is not ready.'
            } elseif ($configurationExit -eq 2) {
                Write-Warning 'Local login worked, but the game schema is missing or incompatible.'
                Write-Host 'For a NEW/EMPTY database only, review the SQL and choose MIGRATE below.'
                Write-Host 'Existing or incompatible tables must be reviewed and backed up first.'
            } else {
                Write-Warning 'The database login or initial configuration was not completed.'
            }

            Write-Host ''
            Write-Host '1 - Retry existing PostgreSQL login'
            Write-Host '2 - Create a NEW dedicated PostgreSQL role/database (requires admin password)'
            Write-Host '3 - Review and explicitly approve schema migration'
            Write-Host '4 - Repair new EMPTY application database credentials (requires admin password)'
            Write-Host '5 - Upgrade EXISTING score tables (verified backup + explicit MIGRATE)'
            Write-Host 'Q - Leave setup for now'
            $choice = Read-Host 'Select 1, 2, 3, 4, 5, or Q'
            switch ($choice.Trim().ToUpperInvariant()) {
                '1' { $requestedMode = 'LOGIN' }
                '2' { $requestedMode = 'CREATE' }
                '3' { $requestedMode = 'MIGRATE' }
                '4' { $requestedMode = 'REPAIR' }
                '5' { $requestedMode = 'UPGRADE' }
                'Q' { Write-Host 'Setup was left unchanged. The game will offer setup again if the database remains offline.'; return }
                default { Write-Warning 'Unrecognized selection. Retrying the existing account login.'; $requestedMode = 'LOGIN' }
            }
        }
        Write-Warning 'Setup attempts finished. The game can open this wizard again later.'
    } finally {
        $wizardMutex.ReleaseMutex()
        $wizardMutex.Dispose()
    }
    return
}

# This branch is intended for a GUI app's short-lived, noninteractive process.
# A visible console is launched ONLY when the saved service is unavailable.
if (Test-Ready) {
    Write-Host 'Local PostgreSQL API already ready.'
    exit 0
}

if (Test-Path -LiteralPath $credentialPath -PathType Leaf) {
    # Saved credentials might recover a stopped API without a password prompt.
    try {
        & $autoScript -HttpPort $HttpPort *> $null
        if ($LASTEXITCODE -eq 0 -and (Test-Ready)) { exit 0 }
    } catch {
        # Continue into the visible setup window.
    }
}

$launchMutex = New-Object Threading.Mutex($false, $launchMutexName)
$hasLaunchMutex = $false
try {
    try {
        $hasLaunchMutex = $launchMutex.WaitOne(0)
    } catch [Threading.AbandonedMutexException] {
        $hasLaunchMutex = $true
    }
    if (-not $hasLaunchMutex) {
        Write-Host 'Database setup launch already in progress.'
        exit 0
    }
    if (Test-WizardAlreadyOpen) {
        Write-Host 'Database setup window is already open.'
        exit 0
    }
    if (-not (Test-Path -LiteralPath $windowsShell -PathType Leaf)) {
        Write-Warning 'Windows PowerShell is unavailable; cannot show the interactive setup window.'
        exit 1
    }

    # Start-Process joins ArgumentList elements with spaces on Windows.
    # Keep the script path quoted (the repository path may contain spaces).
    # -NoExit preserves helpful diagnostics if first-time setup cannot finish.
    $quotedScript = '"' + $PSCommandPath + '"'
    $interactiveArgs = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit',
        '-File', $quotedScript, '-InteractiveSession', '-HttpPort', [string]$HttpPort
    )
    Start-Process -FilePath $windowsShell -ArgumentList $interactiveArgs `
        -WorkingDirectory $repositoryRoot -WindowStyle Normal -ErrorAction Stop | Out-Null

    # Allow the child to acquire the wizard mutex before another game launch.
    for ($tick = 0; $tick -lt 12; $tick++) {
        if (Test-WizardAlreadyOpen) { break }
        Start-Sleep -Milliseconds 100
    }
    Write-Host 'Interactive local database setup window opened.'
    # Exit 0 here means a setup window was launched, NOT the DB is ready.
    # Godot must keep checking /health for PostgreSQL readiness.
    exit 0
} catch {
    Write-Warning 'Could not open the interactive database setup window.'
    exit 1
} finally {
    if ($hasLaunchMutex) { $launchMutex.ReleaseMutex() }
    $launchMutex.Dispose()
}
