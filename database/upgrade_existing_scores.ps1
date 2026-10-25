# Teacher-approved one-time upgrade for an EXISTING 001 PostgreSQL database.
# No schema changes before a verified, local pg_dump backup and typed MIGRATE.
# Never create a new database/role, truncate rows, or change passwords.
param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
$credentials = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'KilosGrammar\db_credentials.xml'
$pgDump = 'C:\Program Files\PostgreSQL\18\bin\pg_dump.exe'
$pgRestore = 'C:\Program Files\PostgreSQL\18\bin\pg_restore.exe'
$passwordPointer = [IntPtr]::Zero
$migrationStarted = $false
$stage = 'checking_local_files'

try {
    foreach ($path in @($python, $credentials, $pgDump, $pgRestore)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw 'Missing local Python, encrypted credentials, or PostgreSQL backup tools.'
        }
    }
    $stage = 'loading_local_credentials'
    $saved = Import-Clixml -LiteralPath $credentials
    if ($saved.Version -ne 1 -or $saved.Host -ne '127.0.0.1' -or
        -not ($saved.Password -is [Security.SecureString]) -or
        $saved.User -cnotmatch '^[a-z_][a-z0-9_]{0,62}$' -or
        $saved.Database -cnotmatch '^[a-z_][a-z0-9_]{0,62}$' -or
        [int]$saved.Port -lt 1 -or [int]$saved.Port -gt 65535) {
        throw 'Stored credentials have an unexpected format.'
    }
    $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($saved.Password)
    $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    $env:KILOS_DB_HOST = '127.0.0.1'
    $env:KILOS_DB_PORT = [string]([int]$saved.Port)
    $env:KILOS_DB_NAME = [string]$saved.Database
    $env:KILOS_DB_USER = [string]$saved.User
    $env:KILOS_DB_PASSWORD = $password
    $env:PGPASSWORD = $password
    $password = $null

    # Read only: reject any schema not exactly the expected pre-upgrade 001.
    $inspection = @'
from database.config import Config
from database.storage import PostgreSQLStore
try:
    with PostgreSQLStore(Config.from_env())._connect() as connection:
        row = connection.execute("""
          SELECT to_regclass('students') IS NOT NULL AS students,
                 to_regclass('student_scores') IS NOT NULL AS scores,
                 EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = current_schema() AND table_name = 'student_scores'
                   AND column_name = 'minigame') AS minigame,
                 EXISTS (SELECT 1 FROM pg_constraint WHERE
                   conrelid = to_regclass('student_scores') AND
                   conname = 'uq_student_scores_minigame_identity') AS new_key,
                 EXISTS (SELECT 1 FROM pg_constraint WHERE
                   conrelid = to_regclass('student_scores') AND
                   conname = 'student_scores_student_id_game_style_game_mode_difficulty_key') AS old_key
        """).fetchone()
        if row['students'] and row['scores'] and row['minigame'] and row['new_key']:
            print('READY')
        elif row['students'] and row['scores'] and not row['minigame'] and not row['new_key'] and row['old_key']:
            print('LEGACY_001')
        else:
            print('REVIEW_REQUIRED')
except Exception:
    print('DATABASE_UNAVAILABLE')
'@
    $stage = 'read_only_schema_preflight'
    Push-Location $root
    try {
        $originalPreference = $ErrorActionPreference
        try {
            # PowerShell 5.1 can turn harmless native stderr into a terminating
            # RemoteException under Stop, even when stderr is redirected.
            $ErrorActionPreference = 'Continue'
            $inspectionResult = $inspection | & $python - 2>$null | Select-Object -Last 1
            $inspectionExit = $LASTEXITCODE
        } finally { $ErrorActionPreference = $originalPreference }
    } finally { Pop-Location }
    if ($inspectionExit -ne 0) { throw 'Read-only schema inspection failed.' }
    if ($inspectionResult -eq 'READY') {
        Write-Host 'The local score database already has the new minigame schema. No migration was performed.'
        exit 0
    }
    if ($inspectionResult -ne 'LEGACY_001') {
        throw 'Existing database is not the verified 001 schema. Manual review is required; no migration was attempted.'
    }
    if ($CheckOnly) {
        Write-Host 'PREFLIGHT=LEGACY_001; verified that a one-time 002 migration is needed. No backup or schema writes performed.'
        exit 0
    }

    Write-Host 'Verified original score schema. This upgrade keeps all student IDs, scores and timestamps.'
    Write-Host 'Historical scores will be tagged Legacy, never guessed to belong to another minigame.'
    Write-Host 'A local backup will be created and verified BEFORE any database schema change.'

    $backupDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'KilosGrammar\backups'
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    # Restrict inherited access: only the Windows user running the game can
    # read these student-containing backups; an ACL failure aborts the upgrade.
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = Get-Acl -LiteralPath $backupDir
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($oldRule in @($acl.Access)) {
        $acl.RemoveAccessRuleSpecific($oldRule) | Out-Null
    }
    $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, [Security.AccessControl.FileSystemRights]::FullControl, $inheritance, [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
    $acl.AddAccessRule($rule)
    (Get-Item -LiteralPath $backupDir).SetAccessControl($acl)

    $backupFile = Join-Path $backupDir ('pre_minigame_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.backup')
    Write-Host 'Backing up the existing database locally; student data will not be printed.'
    $originalPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $pgDump -h 127.0.0.1 -p ([string]$saved.Port) -U ([string]$saved.User) -d ([string]$saved.Database) -F c -f $backupFile *> $null
        $backupExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $originalPreference }
    if ($backupExit -ne 0 -or -not (Test-Path -LiteralPath $backupFile -PathType Leaf) -or (Get-Item -LiteralPath $backupFile).Length -lt 100) {
        throw 'Database backup failed; no migration was attempted.'
    }
    $originalPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $pgRestore --list $backupFile *> $null
        $verifyExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $originalPreference }
    if ($verifyExit -ne 0) { throw 'Backup could not be verified; no migration was attempted.' }
    Write-Host ('VERIFIED BACKUP: ' + $backupFile)
    Write-Host 'The backup remains available even if the following optional migration fails.'
    Write-Host 'Review database/migrations/002_add_minigame.sql now.'
    if ((Read-Host 'Type MIGRATE to upgrade the existing score schema (anything else cancels)') -cne 'MIGRATE') {
        Write-Host 'Upgrade cancelled. Existing students and scores were not changed.'
        exit 2
    }

    $migrationStarted = $true
    Push-Location $root
    try {
        $originalPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $python -m database.migrate --apply-minigame *> $null
            $migrationExit = $LASTEXITCODE
        } finally { $ErrorActionPreference = $originalPreference }
        if ($migrationExit -ne 0) { throw 'The transactional database migration failed.' }
        $originalPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $python -c 'from database.config import Config; from database.storage import PostgreSQLStore; PostgreSQLStore(Config.from_env()).health()' *> $null
            $healthExit = $LASTEXITCODE
        } finally { $ErrorActionPreference = $originalPreference }
        if ($healthExit -ne 0) { throw 'Schema upgrade completed but readiness verification failed.' }
    } finally { Pop-Location }
    Write-Host 'UPGRADE COMPLETE. Existing students and scores are preserved.'
    Write-Host 'The game can now start the local database API automatically on launch.'
} catch {
    Write-Warning 'Local database upgrade did not finish. Review credentials, permissions and backup tools.'
    if ($CheckOnly) {
        Write-Warning ('Safe preflight stage: ' + $stage + '; error type: ' + $_.Exception.GetType().Name)
        if ($stage -eq 'read_only_schema_preflight') {
            Write-Warning ('Safe preflight result: ' + [string]$inspectionResult + '; exit code: ' + [string]$inspectionExit)
        }
    }
    if ($migrationStarted) {
        Write-Warning 'Migration may have been attempted; inspect schema and verified backup before retrying. Do not create another database.'
    } else {
        Write-Warning 'No migration was run and existing database records were not changed.'
    }
    exit 1
} finally {
    foreach ($name in @('KILOS_DB_PASSWORD', 'KILOS_DB_USER', 'KILOS_DB_NAME', 'KILOS_DB_HOST', 'KILOS_DB_PORT', 'PGPASSWORD')) {
        Remove-Item ('Env:' + $name) -ErrorAction SilentlyContinue
    }
    if ($passwordPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer) }
}
