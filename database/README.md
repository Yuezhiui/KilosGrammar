# KILOS GRAMMAR — local PostgreSQL service

This optional Python service exposes the game's student registration, current
completed scores, and leaderboard over **http://127.0.0.1:18765**. It talks
only to a PostgreSQL instance on the local computer. The Godot GUI should use
Godot `HTTPRequest` asynchronously so camera/gameplay rendering stays fluid.

**No database migration or modifications to an existing PostgreSQL instance
have been performed as part of creating these source files.** PostgreSQL
credentials must be supplied locally. The service does not create tables on
startup, and none are stored in the repository.

## Windows setup

Use PowerShell from the `/kilos-grammar` repository root. Python 3.11+ and a
local PostgreSQL installation are required. PostgreSQL must listen on local
port 5432. If PostgreSQL is running already, do not reinstall it.

### One-click setup launched by Godot (Windows)

**Godot should launch this entrypoint when the local API is offline** (default
`http://127.0.0.1:18765/health`):

```text
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<project>\database\setup_from_game.ps1"
```

The parent entrypoint is safe to call from Godot's asynchronous
`OS.create_process()` because it returns after starting a **separate, visible
PowerShell window** with `-NoProfile -ExecutionPolicy Bypass -NoExit -File
"<project>\database\setup_from_game.ps1" -InteractiveSession`. No one has to
manually find or launch PowerShell: the game opens the setup window on the
first use. For an existing app role, it asks for the local PostgreSQL
username, database name, and hidden password. For a **new** application role,
the wizard generates a 256-bit random application password automatically,
asks for the real administrator password, and requires the user to type
`CREATE` before creating the dedicated role/database. The generated password
is not displayed or added to command arguments; successful setup stores it
with the user's Windows DPAPI protection. The wizard also offers explicit
`MIGRATE` after reviewing
`database/migrations/001_initial.sql` and existing tables/backups. It does
not modify existing roles, tables, passwords, or PostgreSQL global settings
without the described confirmations. No cloud services are used.

If an earlier attempt already created the dedicated role/database but stopped
before the generated password was saved, choose **3 — Recover new empty
database credentials** in the automatically opened wizard. This does not
guess or recover the lost password: with the real PostgreSQL administrator
password and typed `RESET`, it verifies that the dedicated app role is an
ordinary login, owns the named database, and that the database contains no
user tables, views, or sequences. Only then may it replace that application's
password with a newly generated strong password. Nonempty databases and
unexpected ownership are rejected. Schema creation still needs a separate
typed `MIGRATE` confirmation after reviewing the migration SQL.

After the user completes setup, the visible wizard calls
`database/start_auto.ps1`, and Godot should continue polling `/health` until
it reports `ok=true`, `data.status=ok`, and `data.database=connected`. The
first call to `setup_from_game.ps1` returning **exit code 0 only means the
window opened or the service was already ready**; it does not mean the
one-time password/setup flow was completed. `-NoExit` keeps helpful
diagnostics visible until the user closes that one-time setup window. Repeated
calls while the wizard is open do not spawn additional password prompts.

For ordinary subsequent launches, Godot may call the quieter entrypoint:

```text
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<project>\database\start_auto.ps1"
```

This launches the existing configured API without prompting. On a new
Windows account, lost credentials, or an offline database, the game can
fall back to `setup_from_game.ps1`. Both only access localhost. The local
Python virtual environment (`database/.venv`) with `psycopg` must already be
present, as on the development machine; if it is missing, the wizard gives
an explanation and does not download/install packages unexpectedly.

### One-time configuration and automatic game launch (optional manual path)

An administrator can also run these commands directly from the project root:

```powershell
.\database\setup_local.ps1
.\database\configure_local.ps1
.\database\start_auto.ps1
Invoke-RestMethod http://127.0.0.1:18765/health
```

`configure_local.ps1` prompts for a local PostgreSQL application username
(default `kilos_app`), database (default `kilos_grammar`) and password without
echoing it. It **tests the PostgreSQL login and reads schema metadata without
changing tables**, then saves the app password as a Windows DPAPI-protected
`SecureString` via `Export-Clixml` in the current Windows user's:

`%LOCALAPPDATA%\KilosGrammar\db_credentials.xml`

This encrypted credential file is **outside the Git repository**, is usable
only by the same Windows user on the same machine, and contains no PostgreSQL
administrator password. The database server and any stored rows stay local.
If your application database doesn't exist, configuration reports whether the
database/role/login seems missing or unauthorized. Never copy the encrypted
credential file to other machines/users; configure separately per Windows user.

To create a **brand-new** dedicated app role and database using local
PostgreSQL administrator credentials, run:

```powershell
.\database\configure_local.ps1 -InitializeNewDatabase -GenerateAppPassword
```

This requires typing `CREATE` and securely entering the existing PostgreSQL
administrator password. It refuses to touch existing role/database names; no
global PostgreSQL authentication settings are changed. When the database
doesn't contain `students` / `student_scores`, review
`database/migrations/001_initial.sql` and backups, then explicitly opt in to
create the schema:

```powershell
.\database\configure_local.ps1 -Migrate
```

It requires typing `MIGRATE` after the SQL review. You can combine flags
`-InitializeNewDatabase -Migrate` for a brand-new empty database, with both
confirmations. A normal configuration **never automatically migrates**.

If the **role and empty database were created**, but their generated app
password was not saved because the initial setup failed, use this explicit
recovery command from a visible interactive PowerShell session, or choose
the recovery option in the game-launched wizard:

```powershell
.\database\configure_local.ps1 -RepairNewAppCredentials -GenerateAppPassword -Migrate
```

The recovery requires typing `RESET`, privately providing the real PostgreSQL
administrator password, and independently typing `MIGRATE` before applying
any schema changes. It does not replace the database or modify its existing
rows. It refuses password recovery for nonempty databases or unexpected role
ownership. Successful recovery saves only the application password in the
current Windows account's DPAPI file.

To start on each game launch without prompts:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\database\start_auto.ps1
```

`start_auto.ps1` reads only the saved credentials, launches the backend in
a hidden, independent Python process, checks that PostgreSQL-backed `/health`
returns ready, and exits promptly. Calling it again while the healthy service
is listening does not start a second copy. If `/health` is offline, a port is
occupied, or the credentials are unavailable, it returns a nonzero exit code
and a safe diagnostic. The launcher does not write the password to the
command line, a log file, or a network service. The game can invoke this
script before trying its local HTTP requests.

### Manual alternative

1. Run `.\database\setup_local.ps1` to create `database/.venv` and install
   `psycopg[binary]` into that environment. The venv is ignored by Git.
   The setup script checks `py -3`, `python`, `python3` with `Get-Command`,
   then `C:\Espressif\tools\python\python.exe` as a local fallback. The
   Python launcher is not required. You can select an interpreter explicitly
   with `.\database\setup_local.ps1 -PythonPath 'C:\Espressif\tools\python\python.exe'`.
   Use `-CheckPythonOnly` to confirm interpreter discovery without creating
   the venv or installing packages. The script checks that pip is running
   inside the project venv before installing; it never installs the database
   driver into the global Python environment.
2. Sign in to local PostgreSQL with your administrative credentials:
   `& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -h 127.0.0.1 -p 5432 -U postgres -d postgres -W`. The PostgreSQL server may
   prompt for its existing password. If `psql` is not in `PATH`, run it from
   your PostgreSQL installation's `bin` directory.
3. For a **new, dedicated database only**, review and run the following in
   `psql` (choose your own secure password). If this database/role already
   exists, inspect it and use the existing credentials instead:

   ```sql
   CREATE ROLE kilos_app LOGIN;
   \password kilos_app
   CREATE DATABASE kilos_grammar OWNER kilos_app;
   ```

4. Review and back up any existing database tables before applying
   `database/migrations/001_initial.sql`. The SQL creates `students`,
   `student_scores`, and an index with `IF NOT EXISTS`; it does not drop or
   truncate tables. **The SQL does not reconcile incompatible pre-existing
   schemas**. On the new dedicated database, run the migration *explicitly*:

   ```powershell
   .\database\run_local.ps1 -Migrate
   ```

5. Start the service in its own PowerShell terminal:

   ```powershell
   .\database\run_local.ps1
   ```

   The script prompts privately for the local PostgreSQL password and sets
   the environment for that process only. Do not put passwords in commits.
   Verify with `Invoke-RestMethod http://127.0.0.1:18765/health`.

The helper scripts default to database `kilos_grammar`, user `kilos_app`, DB
port `5432`, and API port `18765`. `run_local.ps1` also accepts `-DbName`,
`-DbUser`, `-DbPort`, and `-HttpPort` arguments. PostgreSQL authentication
requires a password if the local server is configured that way. Running the
service without a working database returns JSON error HTTP 503, while the
HTTP listener itself still runs.

For other platforms, install the dependency from `database/requirements.txt`,
set environment variables, then run `python -m database.migrate --apply`
only after reviewing the SQL, followed by `python -m database.server`:

| Environment variable | Default / note |
| --- | --- |
| `KILOS_DB_HOST` | `127.0.0.1` (only `localhost` / IPv4/IPv6 loopback permitted) |
| `KILOS_DB_PORT` | `5432` |
| `KILOS_DB_NAME` | `kilos_grammar` |
| `KILOS_DB_USER` | `postgres` for raw Python; PowerShell helper uses `kilos_app` |
| `KILOS_DB_PASSWORD` | No default password; supply in process environment |
| `KILOS_HTTP_PORT` | `18765` |

The HTTP listener always binds to `127.0.0.1`, even if the configured
database hostname is `localhost` or `::1`. This service is intended only
for an application running on the same Windows machine; it is not an
internet-facing server or a student authentication service. Every request
must carry `Host: 127.0.0.1:<API port>` or `Host: localhost:<API port>`;
other Host names receive HTTP 403 to prevent DNS rebinding access. Godot
native requests can omit the `Origin` header. If `Origin` is supplied, it
must exactly match `http://<Host>`; otherwise the request receives 403.
Cross-origin browser preflight requests are not allowed, and the service
never sends `Access-Control-Allow-Origin`. HTTP Host/Origin checks do not
authenticate other local programs; use the service only on a trusted machine.

## HTTP contract

All write bodies use `Content-Type: application/json`; all replies use
`application/json` and the same envelope:

```json
{"ok": true, "data": {"status": "ok", "database": "connected"}, "error": null}
```

Errors set `ok` to `false`, `data` to `null`, and `error` to an object with
`code` and a safe `message`. The service never includes DB connection error
details or passwords in HTTP output. Timestamps use ISO 8601 text.

| Method | Path | Request | Reply `data` |
| --- | --- | --- | --- |
| GET | `/health` | No fields | `{ "status": "ok", "database": "connected" }`, or HTTP 503 if DB/schema unavailable |
| GET | `/students/{student_id}` | URL-encoded student ID | `{ "student": { "student_id", "student_name", "grade_section", "created_at", "updated_at" } }`; 404 if missing |
| POST | `/students` | `{ "student_id", "student_name", "grade_section" }` | `{ "student": {...} }`; 201 if created, 200 if exact same registered identity already exists; 409 if an ID has different details |
| PATCH | `/students/{student_id}` | `{ "student_name"?: string, "grade_section"?: string }` | `{ "student": {...} }`; explicit teacher update only, 404 if ID absent |
| GET | `/scores?student_id=...&game_style=...&game_mode=...&difficulty=...` | All four parameters required | `{ "score": score_object_or_null }` |
| POST | `/rounds/complete` | `{ "student_id", "game_style", "game_mode", "difficulty", "score" }` | `{ "score": {...} }`; 200 success; unknown student 404; invalid score 400 |
| POST | `/scores/completed` | Same as `/rounds/complete` | Compatibility alias with same transactional behavior |
| GET | `/leaderboard` | Optional `game_style`, `game_mode`, `difficulty`, `grade_section`, `limit` | `{ "leaderboard": [entries], "count": integer }` |

Each score object includes `score_id`, `student_id`, `game_style`,
`game_mode`, `difficulty`, `score`, `completed_at`, and `updated_at`.
Each leaderboard entry includes `rank`, `student_id`, `student_name`,
`grade_section`, `game_style`, `game_mode`, `difficulty`, `score`, and
`completed_at`. Leaderboards rank by score descending, then completion
timestamp ascending, then student ID. Filters are exact; omit filters or
send an empty value to show *All*. The default limit is 500, with a maximum
of 500 rows per request. Students may appear once per distinct style/mode/
difficulty combination, because every combination has its own latest score.

Use `game_style` values from the selected grammar topic, e.g. `Noun`;
`game_mode` as `Seconds` or `Lives`; and difficulty as `Easy`, `Normal`, or
`Hard`. These exact case-sensitive strings match the current game payloads.
Student IDs use 1-64 characters of letters, digits, dots, underscores, and
hyphens, starting with a letter/digit. Student name and grade/section must
be nonempty printable strings. Scores must be integers from 0 to 2147483647.

Example from PowerShell with the service running:

```powershell
$payload = @{student_id='KG-0001'; student_name='Rosa'; grade_section='4-A'} | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:18765/students' -ContentType 'application/json' -Body $payload
$completed = @{student_id='KG-0001'; game_style='Noun'; game_mode='Seconds'; difficulty='Easy'; score=15} | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:18765/rounds/complete' -ContentType 'application/json' -Body $completed
Invoke-RestMethod 'http://127.0.0.1:18765/leaderboard'
```

**Completion semantics:** The table has one current score per
`(student_id, game_style, game_mode, difficulty)`. Every completed round
replaces the previous score, including when lower; incomplete or cancelled
rounds must not call `/rounds/complete`. PostgreSQL commits the update
atomically. Student profile data changes only after an explicit PATCH.

## Test without PostgreSQL

Run from the project root with Python 3.11+:

```powershell
python -m unittest discover -s database/tests -v
```

These tests use an in-memory stand-in and mocked connection. No credentials,
live database, migrations, or game files are required or modified.
