# One-time interactive configuration for the Windows user running KILOS GRAMMAR.
# The database is checked read-only. Neither schema nor roles are changed unless
# the caller explicitly requests -Migrate or -InitializeNewDatabase and confirms.
# DPAPI protects the SecureString in %LOCALAPPDATA%\KilosGrammar\db_credentials.xml.
param(
    [string]$DbUser = 'kilos_app',
    [string]$DbName = 'kilos_grammar',
    [int]$DbPort = 5432,
    [string]$AdminUser = 'postgres',
    [switch]$InitializeNewDatabase,
    [switch]$RepairNewAppCredentials,
    [switch]$GenerateAppPassword,
    [switch]$Migrate
)

$ErrorActionPreference = 'Stop'
$virtualPython = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$credentialDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'KilosGrammar'
$credentialPath = Join-Path $credentialDir 'db_credentials.xml'
$psqlPath = 'C:\Program Files\PostgreSQL\18\bin\psql.exe'

function Assert-SafeIdentifier([string]$value, [string]$label) {
    if ($value -cnotmatch '^[a-z_][a-z0-9_]{0,62}$') {
        throw "$label must be a lowercase PostgreSQL identifier (letters, numbers, underscore; first character a letter/underscore)."
    }
}

function Read-Defaulted([string]$label, [string]$default) {
    $answer = Read-Host "$label [$default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $default }
    return $answer.Trim()
}

function Invoke-SafePython([string]$source) {
    # Python's stderr may contain benign native diagnostics in Windows PS 5.1;
    # hide low-level connection diagnostics (which may disclose role/host data).
    # Our Python snippets deliberately print only fixed status codes.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $result = & $virtualPython -c $source 2>$null
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    $lastLine = $result | Select-Object -Last 1
    $statusText = ''
    if ($null -ne $lastLine) { $statusText = [string]$lastLine }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Status = $statusText.Trim()
    }
}

function Show-ConnectionHelp([string]$status) {
    switch ($status) {
        'ROLE_MISSING' { Write-Warning "PostgreSQL user '$DbUser' is absent. Create a dedicated role/database with -InitializeNewDatabase, or use an existing role." }
        'DATABASE_MISSING' { Write-Warning "Database '$DbName' does not exist. Use -InitializeNewDatabase only for a new dedicated pair, or select an existing database." }
        'AUTH_FAILED' { Write-Warning "PostgreSQL rejected the username/password (a nonexistent role can also appear as an authentication failure). Verify the role and password using psql." }
        'NO_SERVER' { Write-Warning "PostgreSQL on 127.0.0.1:$DbPort is unreachable. Verify the postgresql-x64-18 Windows service and port 5432." }
        'PERMISSION_DENIED' { Write-Warning "The PostgreSQL user can connect but lacks permission to query the game's tables. Grant access with the database administrator." }
        default { Write-Warning 'Could not verify local PostgreSQL credentials. Check PostgreSQL login, database name and permissions.' }
    }
    if (Test-Path -LiteralPath $psqlPath -PathType Leaf) {
        Write-Host "Check login with: & '$psqlPath' -h 127.0.0.1 -p $DbPort -U $DbUser -d $DbName -W"
        Write-Host "Admin console: & '$psqlPath' -h 127.0.0.1 -p $DbPort -U $AdminUser -d postgres -W"
        Write-Host 'Within the psql admin console, run \du to list roles and \l to list databases.'
    }
    Write-Host 'For manual creation in the PostgreSQL admin console (only when the role/database do not exist):'
    Write-Host "  CREATE ROLE $DbUser LOGIN;"
    Write-Host "  \password $DbUser    (psql prompts for a private password)"
    Write-Host "  CREATE DATABASE $DbName OWNER $DbUser;"
    Write-Host 'Do not run CREATE statements against an existing role/database; choose -InitializeNewDatabase for guided creation.'
}

if (-not (Test-Path -LiteralPath $virtualPython -PathType Leaf)) {
    throw 'Python virtual environment is missing. Run .\database\setup_local.ps1 first.'
}
if ($DbPort -lt 1 -or $DbPort -gt 65535) { throw 'DbPort must be 1-65535.' }
if ($InitializeNewDatabase -and $RepairNewAppCredentials) {
    throw '-InitializeNewDatabase and -RepairNewAppCredentials cannot be combined.'
}
if ($GenerateAppPassword -and -not ($InitializeNewDatabase -or $RepairNewAppCredentials)) {
    throw '-GenerateAppPassword is only valid when creating or repairing a brand-new local application role.'
}
if ($RepairNewAppCredentials -and -not $GenerateAppPassword) {
    throw 'Repair of a new application role requires -GenerateAppPassword.'
}

# Validate the local Python environment without installing any packages.
$probe = Invoke-SafePython 'import sys, psycopg; sys.exit(0 if sys.prefix != sys.base_prefix else 1)'
if ($probe.ExitCode -ne 0) {
    throw 'Python virtual environment/psycopg is invalid. Run .\database\setup_local.ps1 first.'
}

$DbUser = Read-Defaulted 'Local PostgreSQL application username' $DbUser
$DbName = Read-Defaulted 'Local PostgreSQL database name' $DbName
Assert-SafeIdentifier $DbUser 'Username'
Assert-SafeIdentifier $DbName 'Database name'
Assert-SafeIdentifier $AdminUser 'Admin username'

if ($GenerateAppPassword) {
    # 256 random bits, encoded as a URL-safe PostgreSQL password. The value is
    # never displayed, passed on the command line, or persisted as plaintext.
    $randomBytes = New-Object byte[] 32
    $randomGenerator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $randomGenerator.GetBytes($randomBytes)
        $passwordText = [Convert]::ToBase64String($randomBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        $securePassword = ConvertTo-SecureString -String $passwordText -AsPlainText -Force
    } finally {
        [Array]::Clear($randomBytes, 0, $randomBytes.Length)
        $randomGenerator.Dispose()
        $passwordText = $null
    }
    Write-Host 'Generated a strong application password. It will be saved encrypted only after PostgreSQL login succeeds.'
} else {
    $securePassword = Read-Host "Password for '$DbUser' (input hidden)" -AsSecureString
}
$passwordPointer = [IntPtr]::Zero
$env:KILOS_DB_HOST = '127.0.0.1'
$env:KILOS_DB_PORT = [string]$DbPort
$env:KILOS_DB_USER = $DbUser
$env:KILOS_DB_NAME = $DbName

$checkSource = @'
import os, sys
try:
    import psycopg
    connection = psycopg.connect(
        host='127.0.0.1', port=int(os.environ['KILOS_DB_PORT']),
        user=os.environ['KILOS_DB_USER'], dbname=os.environ['KILOS_DB_NAME'],
        password=os.environ['KILOS_DB_PASSWORD'], connect_timeout=3,
        options='-c default_transaction_read_only=on',
    )
    with connection:
        with connection.cursor() as cursor:
            # Use single quotes throughout -c source. Windows PowerShell 5.1
            # otherwise strips embedded double quotes in native argv.
            cursor.execute('SELECT to_regclass(%s), to_regclass(%s)', ('students', 'student_scores'))
            schemas = cursor.fetchone()
            if None in schemas:
                print('SCHEMA_MISSING')
                sys.exit(0)
            try:
                cursor.execute('SELECT student_id, student_name, grade_section FROM students LIMIT 0')
                cursor.execute('SELECT score_id, student_id, game_style, game_mode, difficulty, score FROM student_scores LIMIT 0')
            except psycopg.Error:
                print('SCHEMA_INCOMPATIBLE')
                sys.exit(0)
    print('READY')
except psycopg.Error as exc:
    message = str(exc).lower()
    if 'role ' in message and 'does not exist' in message: print('ROLE_MISSING')
    elif 'database ' in message and 'does not exist' in message: print('DATABASE_MISSING')
    elif 'password authentication failed' in message or exc.sqlstate in ('28P01', '28000'): print('AUTH_FAILED')
    elif 'connection refused' in message or 'timed out' in message: print('NO_SERVER')
    elif exc.sqlstate == '42501' or 'permission denied' in message: print('PERMISSION_DENIED')
    else: print('CONNECT_FAILED')
    sys.exit(2)
except Exception:
    print('CONNECT_FAILED')
    sys.exit(2)
'@

$bootstrapSource = @'
import os, sys
try:
    import psycopg
    from psycopg import sql
    user = os.environ['KILOS_DB_USER']
    dbname = os.environ['KILOS_DB_NAME']
    with psycopg.connect(
        host='127.0.0.1', port=int(os.environ['KILOS_DB_PORT']),
        user=os.environ['KILOS_ADMIN_USER'], dbname='postgres',
        password=os.environ['KILOS_ADMIN_PASSWORD'], connect_timeout=3,
        autocommit=True,
    ) as connection:
        with connection.cursor() as cursor:
            cursor.execute('SELECT 1 FROM pg_roles WHERE rolname = %s', (user,))
            role_exists = cursor.fetchone() is not None
            cursor.execute('SELECT 1 FROM pg_database WHERE datname = %s', (dbname,))
            database_exists = cursor.fetchone() is not None
            # No writes when either name already exists. Existing identities
            # must never be silently modified or replaced.
            if role_exists or database_exists:
                print('RESOURCE_EXISTS')
                sys.exit(3)
            cursor.execute(sql.SQL('CREATE ROLE {} LOGIN PASSWORD {}').format(
                sql.Identifier(user), sql.Literal(os.environ['KILOS_DB_PASSWORD'])))
            cursor.execute(sql.SQL('CREATE DATABASE {} OWNER {}').format(
                sql.Identifier(dbname), sql.Identifier(user)))
    print('CREATED')
except psycopg.Error as exc:
    message = str(exc).lower()
    if 'password authentication failed' in message or exc.sqlstate in ('28P01', '28000'): print('ADMIN_AUTH_FAILED')
    elif 'connection refused' in message or 'timed out' in message: print('NO_SERVER')
    elif exc.sqlstate == '42501' or 'permission denied' in message: print('ADMIN_PERMISSION_DENIED')
    else: print('ADMIN_FAILURE')
    sys.exit(2)
except Exception:
    print('ADMIN_FAILURE')
    sys.exit(2)
'@

# Emergency recovery ONLY for the just-created dedicated role+database when
# bootstrap succeeded but configuration stopped before saving the random app
# password. No role deletion, database/table modification, or global auth change.
$repairSource = @'
import os, sys
try:
    import psycopg
    from psycopg import sql
    user = os.environ['KILOS_DB_USER']
    dbname = os.environ['KILOS_DB_NAME']
    common = {
        'host': '127.0.0.1',
        'port': int(os.environ['KILOS_DB_PORT']),
        'user': os.environ['KILOS_ADMIN_USER'],
        'password': os.environ['KILOS_ADMIN_PASSWORD'],
        'connect_timeout': 3,
    }
    with psycopg.connect(dbname='postgres', **common) as admin:
        with admin.cursor() as cursor:
            cursor.execute('SELECT rolcanlogin, rolsuper, rolcreatedb, rolcreaterole FROM pg_roles WHERE rolname = %s', (user,))
            role = cursor.fetchone()
            cursor.execute('SELECT pg_get_userbyid(datdba), datistemplate FROM pg_database WHERE datname = %s', (dbname,))
            database = cursor.fetchone()
            if not role or role != (True, False, False, False) or not database or database != (user, False):
                print('REPAIR_REFUSED_OWNER')
                sys.exit(3)
    with psycopg.connect(dbname=dbname, **common) as target:
        with target.cursor() as cursor:
            cursor.execute(
                'SELECT COUNT(*) FROM pg_class AS c '
                'JOIN pg_namespace AS n ON n.oid = c.relnamespace '
                'WHERE n.nspname NOT LIKE %s AND n.nspname <> %s '
                'AND c.relkind IN (%s, %s, %s, %s, %s, %s)',
                ('pg_%', 'information_schema', 'r', 'p', 'v', 'm', 'f', 'S'),
            )
            if cursor.fetchone()[0] != 0:
                print('REPAIR_REFUSED_NONEMPTY')
                sys.exit(3)
    with psycopg.connect(dbname='postgres', autocommit=True, **common) as admin:
        with admin.cursor() as cursor:
            cursor.execute(sql.SQL('ALTER ROLE {} WITH PASSWORD {}').format(
                sql.Identifier(user), sql.Literal(os.environ['KILOS_DB_PASSWORD'])))
    print('REPAIRED')
except psycopg.Error as exc:
    message = str(exc).lower()
    if 'password authentication failed' in message or exc.sqlstate in ('28P01', '28000'): print('ADMIN_AUTH_FAILED')
    elif 'connection refused' in message or 'timed out' in message: print('NO_SERVER')
    elif exc.sqlstate == '42501' or 'permission denied' in message: print('ADMIN_PERMISSION_DENIED')
    else: print('ADMIN_FAILURE')
    sys.exit(2)
except Exception:
    print('ADMIN_FAILURE')
    sys.exit(2)
'@

try {
    $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $env:KILOS_DB_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)

    if ($InitializeNewDatabase) {
        if ($DbUser -eq $AdminUser -or $DbName -eq 'postgres') {
            throw 'New database initialization requires a dedicated app user and a database name other than postgres.'
        }
        Write-Host "Create ONLY a new PostgreSQL role '$DbUser' and database '$DbName' on 127.0.0.1:$DbPort."
        Write-Host 'If either already exists, the script stops without changing that existing resource.'
        if ((Read-Host "Type CREATE to confirm") -cne 'CREATE') {
            throw 'Initialization cancelled. No role or database was created.'
        }
        $adminPassword = Read-Host "Password for PostgreSQL administrator '$AdminUser' (not saved)" -AsSecureString
        $adminPointer = [IntPtr]::Zero
        try {
            $adminPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPassword)
            $env:KILOS_ADMIN_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($adminPointer)
            $env:KILOS_ADMIN_USER = $AdminUser
            $bootstrap = Invoke-SafePython $bootstrapSource
        } finally {
            Remove-Item Env:KILOS_ADMIN_PASSWORD -ErrorAction SilentlyContinue
            Remove-Item Env:KILOS_ADMIN_USER -ErrorAction SilentlyContinue
            if ($adminPointer -ne [IntPtr]::Zero) {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($adminPointer)
            }
        }
        if ($bootstrap.Status -ne 'CREATED' -or $bootstrap.ExitCode -ne 0) {
            if ($bootstrap.Status -eq 'RESOURCE_EXISTS') {
                Write-Warning 'An application role or database with this name already exists. Existing identities and tables were left untouched.'
            } elseif ($bootstrap.Status -eq 'ADMIN_AUTH_FAILED') {
                Write-Warning 'PostgreSQL rejected the administrator password. Confirm it with the local psql console.'
            } elseif ($bootstrap.Status -eq 'ADMIN_PERMISSION_DENIED') {
                Write-Warning 'The supplied administrator cannot create roles/databases (CREATEROLE/CREATEDB privileges required).'
            } else {
                Write-Warning 'Database initialization failed. An app role might exist from a partial CREATE operation; inspect pg_roles and pg_database before retrying.'
            }
            Show-ConnectionHelp $bootstrap.Status
            exit 1
        }
        Write-Host "Created local PostgreSQL role '$DbUser' and database '$DbName'. Schema creation remains a separate, explicit step."
    } elseif ($RepairNewAppCredentials) {
        if ($DbUser -eq $AdminUser -or $DbName -eq 'postgres') {
            throw 'Credential recovery requires a dedicated application role and database other than postgres.'
        }
        Write-Host "REPAIR REQUEST: reset ONLY the generated password for role '$DbUser' in the new local database '$DbName'."
        Write-Host 'Recovery is denied unless the role is an ordinary login, owns that exact database, and that database has NO user tables/views/sequences.'
        Write-Host 'The database and any pre-existing data are never deleted or overwritten. Administrator password will be requested privately.'
        if ((Read-Host 'Type RESET to explicitly approve this limited app-role password reset') -cne 'RESET') {
            throw 'Credential recovery cancelled. No password or database changes were made.'
        }
        $adminPassword = Read-Host "Password for PostgreSQL administrator '$AdminUser' (not saved)" -AsSecureString
        $adminPointer = [IntPtr]::Zero
        try {
            $adminPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPassword)
            $env:KILOS_ADMIN_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($adminPointer)
            $env:KILOS_ADMIN_USER = $AdminUser
            $repair = Invoke-SafePython $repairSource
        } finally {
            Remove-Item Env:KILOS_ADMIN_PASSWORD -ErrorAction SilentlyContinue
            Remove-Item Env:KILOS_ADMIN_USER -ErrorAction SilentlyContinue
            if ($adminPointer -ne [IntPtr]::Zero) {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($adminPointer)
            }
        }
        if ($repair.Status -ne 'REPAIRED' -or $repair.ExitCode -ne 0) {
            if ($repair.Status -eq 'REPAIR_REFUSED_NONEMPTY') {
                Write-Warning 'Credential repair REFUSED: the database is not empty. Existing tables/data were not changed.'
            } elseif ($repair.Status -eq 'REPAIR_REFUSED_OWNER') {
                Write-Warning 'Credential repair REFUSED: dedicated role ownership or role privileges do not match an initial blank setup.'
            } elseif ($repair.Status -eq 'ADMIN_AUTH_FAILED') {
                Write-Warning 'The existing PostgreSQL administrator password was rejected.'
            } else {
                Write-Warning 'Could not safely repair dedicated application credentials. Inspect roles/database in the local PostgreSQL admin console.'
            }
            exit 1
        }
        Write-Host "Reset only the new app-role password for '$DbUser'. Verifying login before DPAPI save..."
    }

    $status = Invoke-SafePython $checkSource
    if ($status.ExitCode -ne 0) {
        Show-ConnectionHelp $status.Status
        exit 1
    }

    # Save only after the PostgreSQL login succeeds. DPAPI encrypts SecureString
    # for this Windows account on this machine; the administrator password is
    # never part of the saved object.
    $saved = [pscustomobject]@{
        Version = 1
        Host = '127.0.0.1'
        Port = $DbPort
        Database = $DbName
        User = $DbUser
        Password = $securePassword
    }
    if (-not (Test-Path -LiteralPath $credentialDir)) {
        New-Item -ItemType Directory -Path $credentialDir -Force | Out-Null
    }
    $saved | Export-Clixml -LiteralPath $credentialPath -Force
    Write-Host "Saved encrypted local database credentials for this Windows account: $credentialPath"

    if ($status.Status -eq 'READY') {
        Write-Host 'PostgreSQL authentication and KILOS GRAMMAR schema are ready.'
    } else {
        if ($status.Status -eq 'SCHEMA_INCOMPATIBLE') {
            Write-Warning 'Existing tables do not match the expected schema. Review and back up them manually; do not force the initial migration.'
            exit 2
        }
        Write-Warning 'PostgreSQL login works, but KILOS GRAMMAR tables are missing. The API /health will report offline until migrated.'
        Write-Host "Review first: $PSScriptRoot\migrations\001_initial.sql"
        if (-not $Migrate) {
            Write-Host 'After reviewing schema/backup, rerun configure_local.ps1 with -Migrate (credentials will be prompted again).'
            exit 2
        }
    }

    if ($Migrate -and $status.Status -ne 'READY') {
        Write-Host 'Migration is an explicit write operation. Existing tables are never dropped, but incompatible schemas require manual review.'
        if ((Read-Host 'Type MIGRATE after reviewing 001_initial.sql and existing backups') -cne 'MIGRATE') {
            throw 'Migration cancelled. Credentials were saved; database tables were not changed.'
        }
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            Push-Location $repositoryRoot
            try {
                & $virtualPython -m database.migrate --apply 2>$null
                $migrationExitCode = $LASTEXITCODE
            } finally {
                Pop-Location
            }
        } finally {
            $ErrorActionPreference = $previousPreference
        }
        if ($migrationExitCode -ne 0) {
            throw 'Migration failed; verify table permissions/schema compatibility. Existing tables were not intentionally modified.'
        }
        $check = Invoke-SafePython $checkSource
        if ($check.ExitCode -ne 0 -or $check.Status -ne 'READY') {
            throw 'Schema migration returned, but readiness validation failed; inspect database tables and permissions.'
        }
        Write-Host 'Schema migration successful; database is ready.'
    }

    Write-Host 'Start the localhost backend without prompts: .\database\start_auto.ps1'
} finally {
    Remove-Item Env:KILOS_DB_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:KILOS_DB_USER -ErrorAction SilentlyContinue
    Remove-Item Env:KILOS_DB_NAME -ErrorAction SilentlyContinue
    Remove-Item Env:KILOS_DB_HOST -ErrorAction SilentlyContinue
    Remove-Item Env:KILOS_DB_PORT -ErrorAction SilentlyContinue
    if ($passwordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }
}
