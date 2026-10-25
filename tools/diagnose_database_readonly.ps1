# Inspect LOCAL database availability without changing accounts, schema, rows,
# service configuration, or stored credentials. Do not print secrets or DSNs.
$ErrorActionPreference = 'Stop'
$credentialPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'KilosGrammar\db_credentials.xml'
$pythonPath = Join-Path $PSScriptRoot '..\database\.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $credentialPath -PathType Leaf)) { Write-Output 'STATUS=credentials_missing'; exit 2 }
if (-not (Test-Path -LiteralPath $pythonPath -PathType Leaf)) { Write-Output 'STATUS=python_missing'; exit 2 }
$pointer = [IntPtr]::Zero
try {
    $saved = Import-Clixml -LiteralPath $credentialPath
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($saved.Password)
    $env:KILOS_DB_HOST = '127.0.0.1'
    $env:KILOS_DB_PORT = [string]([int]$saved.Port)
    $env:KILOS_DB_NAME = [string]$saved.Database
    $env:KILOS_DB_USER = [string]$saved.User
    $env:KILOS_DB_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    @'
from database.config import Config
from database.storage import PostgreSQLStore

try:
    config = Config.from_env()
    print('STATUS=connected')
    with PostgreSQLStore(config)._connect() as conn:
        metadata = conn.execute("""
            SELECT current_database() IS NOT NULL AS connected,
                   to_regclass('students') IS NOT NULL AS students,
                   to_regclass('student_scores') IS NOT NULL AS scores,
                   EXISTS (SELECT 1 FROM information_schema.columns
                           WHERE table_schema = current_schema()
                             AND table_name = 'student_scores' AND column_name = 'minigame') AS minigame,
                   EXISTS (SELECT 1 FROM pg_constraint
                           WHERE conrelid = to_regclass('student_scores')
                             AND conname = 'uq_student_scores_minigame_identity') AS minigame_identity,
                   EXISTS (SELECT 1 FROM pg_constraint
                           WHERE conrelid = to_regclass('student_scores')
                             AND conname = 'student_scores_student_id_game_style_game_mode_difficulty_key') AS old_identity
        """).fetchone()
        for key in ('connected', 'students', 'scores', 'minigame', 'minigame_identity', 'old_identity'):
            print('SCHEMA_' + key.upper() + '=' + str(bool(metadata[key])))
        if metadata['students'] and metadata['scores']:
            print('STUDENT_COUNT=' + str(conn.execute('SELECT count(*) FROM students').fetchone()['count']))
            print('SCORE_COUNT=' + str(conn.execute('SELECT count(*) FROM student_scores').fetchone()['count']))
except Exception as exc:
    # Type and SQLSTATE are diagnostic only. Never echo exception messages,
    # usernames, database names, server output or passwords.
    print('STATUS=error')
    print('ERROR_TYPE=' + type(exc).__name__)
    print('ERROR_SQLSTATE=' + str(getattr(exc, 'sqlstate', '') or 'none'))
'@ | & $pythonPath -
} catch {
    Write-Output 'STATUS=credentials_unreadable_or_runtime_failed'
} finally {
    foreach ($key in @('KILOS_DB_HOST','KILOS_DB_PORT','KILOS_DB_NAME','KILOS_DB_USER','KILOS_DB_PASSWORD')) {
        Remove-Item ('Env:' + $key) -ErrorAction SilentlyContinue
    }
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}
