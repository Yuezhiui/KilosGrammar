# KilosGrammar: reproducible offline Windows release

This folder prepares a **Windows x64 Godot 4.7.2 desktop EXE** and the accompanying
offline Python/YOLO and PostgreSQL prerequisites. A school computer runs the
exported EXE **without a Godot editor or Internet connection**. This is a
preparation/build process: the required signed installers, wheels, model and
their redistribution permissions must be supplied and reviewed before release.

## What the exported folder contains

```text
KilosGrammar-win-x64/
  KilosGrammar.exe + KilosGrammar.pck     Godot player and game resources
  Play KilosGrammar.cmd                  supported game launch entrypoint
  Setup Offline.cmd                      one-time teacher offline setup
  Launch-Game.ps1, Install-OnSchoolPC.ps1, Test-OfflinePayload.ps1
  requirements-offline.txt
  database/                               loose API, migrations, DPAPI wizard
    .venv/                                CREATED ONLY ON THE SCHOOL PC
  ui/vision/pose_worker.py               loose helper required by OS.create_process
  ui/vision/student_lock.py              Python import used by pose_worker
  ui/vision/gesture_detector.py          offline single-hand and airplane-pose classifier
  runtime/models/yolo26n-pose.pt         verified model beside the EXE
  offline/
    manifest.json                        hashes for ALL offline input artifacts
    models/yolo26n-pose.pt                source of teacher's per-user model
    wheels/*.whl                          complete CPython 3.11 win_amd64 wheelhouse
    installers/python-3.11.*-amd64.exe   official full Python installer
    installers/postgresql-18*-windows-x64.exe  approved PostgreSQL 18 installer
    licenses/                             reviewed third-party notices/terms
  manifest.json                           canonical SHA-256 inventory of ALL shipped files
  release-manifest.json                   Godot EXE/PCK/model SHA-256 summary
```

The Godot PCK is NOT a Python executable or a virtual environment. Windows
`venv` stores machine-specific interpreter paths in `pyvenv.cfg`; copying the
developer's `database/.venv` to another PC is unsupported. Setup creates a
new target-local `.venv` from the staged wheels. CPU-only PyTorch is the
baseline; RTX/CUDA drivers or performance are not guaranteed.

`ui/vision/pose_service.gd` invokes the external worker using a real filesystem
path resolved from `res://ui/vision/pose_worker.py`; therefore the builder
deliberately adds it and `student_lock.py` as loose files. It also stages the
model at `runtime/models/yolo26n-pose.pt` beside the EXE for the exported
service's absolute-model lookup, and setup copies a verified model into the
current Windows user's Godot `user://pose_models` directory for compatibility.

## 1. Prepare on a connected build PC

1. Install **Godot 4.7.2** and its EXACT Windows x86_64 **release and debug
   export templates**, then confirm BOTH files exist inside
   `%APPDATA%\Godot\export_templates\4.7.2.stable\`:
   `windows_release_x86_64.exe` and `windows_debug_x86_64.exe`.
   Godot's export validation requires both even for `--export-release`.
2. Obtain the official **64-bit CPython 3.11 full Windows offline installer**,
   for example `python-3.11.9-amd64.exe`. It must support `venv` and
   `ensurepip`; the embeddable ZIP does **not** meet this release contract.
   CPython minor must be **3.11** even if a newer interpreter is available.
3. Obtain a verified **PostgreSQL 18 Windows x64 offline installer** from the
   supported EDB/PostgreSQL provider. Stage the installer; do not copy an
   installed `C:\Program Files\PostgreSQL\18` directory or its `data` tree.
   An existing school-approved PostgreSQL 18 service is also acceptable if
   it is running locally under the expected standard service name.
4. Obtain the legally distributable `yolo26n-pose.pt` checkpoint. The
   development machine currently caches it under
   `%APPDATA%\Godot\app_userdata\KilosGrammar\pose_models\yolo26n-pose.pt`.
   Inspect its origin, license and checksum before staging. Offline school
   devices **cannot download weights** on first launch.
5. Create a COMPLETE Windows x64 **CPython 3.11** `.whl` wheelhouse for
   `requirements-offline.txt` and all transitive dependencies, including
   a compatible CPU build of **torch + torchvision**, Ultralytics, OpenCV,
   LAP, NumPy and Psycopg binary. On a connected preparation computer, one
   possible route is:

   ```powershell
   py -3.11 -m pip download --only-binary=:all: --dest C:\offline-wheels --index-url https://download.pytorch.org/whl/cpu 'torch==2.6.0' 'torchvision==0.21.0'
   py -3.11 -m pip download --only-binary=:all: --dest C:\offline-wheels --find-links C:\offline-wheels -r release\windows\requirements-offline.txt
   ```

   Use a Windows x64 Python 3.11 build PC so wheels match the target. The
   PyTorch CPU index is only needed for staging on the connected build PC.
   Review the resolved wheel set for compatibility/licensing before release.
   The `manifest.json` hashes the *actual* wheel files, so those bytes remain
   fixed for a given release; direct dependencies are pinned in the requirements.
   The build runs `Test-OfflineWheels.ps1` with pip's no-index `--dry-run
   --ignore-installed` to verify transitive wheel resolution without installing
   anything on the build PC.

6. Collect required package notices, font author/license texts, Godot MIT
   license notice, PostgreSQL/EDB installer terms and Ultralytics/model license
   obligations in an approved local folder. Permission to redistribute the
   Ultralytics code and weights (AGPL-3.0 or another applicable license) must
   be confirmed for the chosen distribution model. Also review artwork and
   sound provenance. The optional user-provided **Wii Fit** soundtrack is
   excluded by the export preset and must not ship without rights.

Stage the vetted files (no network access or machine install occurs here):

```powershell
.\release\windows\Stage-OfflinePrerequisites.ps1 `
  -ModelPath 'C:\approved\yolo26n-pose.pt' `
  -PythonInstallerPath 'C:\approved\python-3.11.9-amd64.exe' `
  -PostgreSqlInstallerPath 'C:\approved\postgresql-18.0-1-windows-x64.exe' `
  -WheelhouseDirectory 'C:\offline-wheels' `
  -LicenseDirectory 'C:\approved\licenses'
```

Staging uses a uniquely named temporary directory and creates the ignored
`release/windows/offline/manifest.json` only after the staged artifacts pass
hash verification. Existing staged files are never overwritten. The manifest
is an integrity inventory, **not a
digital signature** or grant of redistribution rights. Inspect Authenticode
signatures/original supplier checksums of EXE installers separately. To change
any staged file, intentionally remove the old staged copy, then regenerate the
manifest by running the staging command again.

## 2. Preflight and export

```powershell
.\release\windows\Build-OfflineRelease.ps1 -GodotExe 'C:\path\Godot_v4.7.2-stable_win64_console.exe' -PreflightOnly
.\release\windows\Build-OfflineRelease.ps1 -GodotExe 'C:\path\Godot_v4.7.2-stable_win64_console.exe'
```

Both commands stop with actionable diagnostics if a required template/source,
model, installer, wheel, or checksum is missing. Export uses the checked-in
`export_presets.cfg` `Windows Desktop` preset and generates the paired EXE/PCK.
The release folder appears at `release/windows/out/KilosGrammar-win-x64/`.
It contains a canonical root **`manifest.json`** generated only after successful
EXE/PCK export and dependency staging. `release-manifest.json` is a separate
summary for backward compatibility. `Test-ReleasePackage.ps1` verifies the
finished output and checks all listed files against real SHA-256 digests.
If BUG-007 reports missing `manifest.json` while the EXE/PCK or offline
dependencies are also absent, **no complete release exists yet**; use the
staging/build preflight and fix missing prerequisites. Never generate an empty
manifest or declare a failed export ready for classrooms.
For safety an existing output/staging folder is **never overwritten**. Review,
archive or rename it yourself before rebuilding.

The builder never starts a database, accesses student records, touches saved
DPAPI credentials, installs dependencies or starts camera capture. A completed
build is not a substitute for a genuine second-PC acceptance test.

## 3. Install on a different school PC with no Internet

Transfer the **entire** `KilosGrammar-win-x64` folder to Windows 11 x64.
Do not run from inside a ZIP archive. No Godot editor is required on that PC.

1. Run the **reviewed** PostgreSQL 18 offline installer with a school
   administrator (unless an approved PostgreSQL 18 x64 service already runs).
   Follow its interactive setup, keep PostgreSQL on local port 5432, and
   store/administer its admin password privately. The release installer does
   **not** claim PostgreSQL is a portable copy, does not edit `pg_hba.conf`,
   and never runs the EDB installer without an administrator choosing it.
2. Run the reviewed CPython 3.11 x64 full installer if Python 3.11 is not yet
   installed. Select an install mode with `venv` / `ensurepip`. Offline mode
   requires no external package repository after staging.
3. Double-click **Setup Offline.cmd**. It verifies PostgreSQL's service,
   verifies EVERY staged SHA-256, creates only the release-folder-local
   `database/.venv`, installs packages with `pip --no-index --no-cache-dir`,
   verifies key Python imports, and copies the model into the current Windows
   user's Godot model cache. If an unknown `.venv` or conflicting model exists,
   setup stops and preserves it. A failed dependency install must be diagnosed
   by the technician before retrying; never copy another computer's `.venv`.
4. Double-click **Play KilosGrammar.cmd**. This launches the Godot desktop
   EXE with `KILOSGRAMMAR_PYTHON` pointing to this computer's local `.venv`.
   The application has an existing database auto-start / one-time setup
   wizard (`database/start_auto.ps1`, `setup_from_game.ps1`). It can open the
   visible, private **DPAPI** credentials wizard. For a new dedicated database
   the teacher must approve `CREATE` and `MIGRATE` after reviewing its proposed
   role/schema. For an existing database, do not initialize or migrate until
   its current structure and backup are reviewed. No admin password is saved.

On that Windows account, DPAPI stores application credentials under
`%LOCALAPPDATA%\KilosGrammar\db_credentials.xml`. That file belongs to the
**same user on the same PC** and must not be copied between machines or
included in release media. Once configured and local PostgreSQL is running,
the game's watchdog can relaunch its local Python API as needed. Both API
and camera packets are loopback-only. The classroom should retain a current
database backup procedure independent of this release folder.

## 4. Final release acceptance on the actual target computer

Verify the following with Internet disabled: `Setup Offline.cmd` completes;
`Play KilosGrammar.cmd` opens the game; API `/health` reports database
connected on `127.0.0.1:18765`; a teacher can register/find/update a student,
finish a round, view persistent scores/leaderboard, import/export CSV as
implemented, and restart without losing records; camera permission is
available; the supplied checkpoint loads without downloading; a single
student calibrates and controls each game. Check both CPU capability and GPU
driver/hardware, Windows privacy settings, display resolution, and startup
after a real PC reboot. The EXE can be launched directly, but the supplied
`Play KilosGrammar.cmd` is required to select the packaged Python environment
for reliable camera execution until the game's native Python discovery also
supports that release location automatically.

Release status remains **NOT READY** until export templates, full offline
wheelhouse/installers, redistribution review and another-computer acceptance
have been verified. Python package versions, CUDA support and operating system
compatibility must match the accepted target machine.

Reference sources: [Godot Windows export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_windows.html),
[Godot command-line export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html),
[PostgreSQL Windows installers](https://www.postgresql.org/download/windows/),
[Ultralytics licensing](https://www.ultralytics.com/license).
