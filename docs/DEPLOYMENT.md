# KilosGrammar — deployment and release acceptance

This document is the **release gate** for an offline Windows school deployment. It complements the project [README](../README.md), the authoritative [Windows packaging instructions](../release/windows/README.md), and the [local PostgreSQL setup and migration guide](../database/README.md). It is **not evidence** that a distributable installer has been built or independently accepted.

## Verified documentation status (2026-10-30)

| Item | Status / interpretation |
| --- | --- |
| Public source beta | `v0.3.0-beta.1` is reported by the local `origin/main:VERSION` tracking ref. This is a **source beta**, not a signed Windows installer. |
| Local checkout metadata | `VERSION` and `project.godot` now both read `0.3.0-beta.1`. [Older build notes](BUILD_VERSION.md) refer to an earlier beta and remain historical. |
| Windows EXE version resource | [`export_presets.cfg`](../export_presets.cfg) now specifies `0.3.0.0` file/product metadata, but these settings are **not proof of an exported Windows binary**. |
| Build outputs | No finished `release/windows/out/KilosGrammar-win-x64/KilosGrammar.exe`, `KilosGrammar.pck` or canonical `manifest.json` was present during this documentation review. |
| Offline prerequisites | `release/windows/offline/manifest.json` was absent. A complete approved offline payload is therefore **not evidenced** here. |
| External acceptance | Successful automated/mock tests are not proof of webcam behavior, dependable pose FPS, classroom performance, or functioning installation on a second disconnected PC. |

**Release classification: NOT YET ACCEPTED.** Do not attach a fabricated EXE, claim that a packaged installer is ready, or publish a release based only on source features or mocked test counts. Re-evaluate the actual bytes and signoffs at build time.

## 1. Local source demonstration (not an offline installer)

1. Install **Godot 4.7.2 stable**. Import [`project.godot`](../project.godot) into the editor and run the project with **F5**.
2. The three scene-driven games and UI can be inspected without distributing a native Windows installer. A classroom-style Play demonstration with live tracking requires a local **Python/YOLO pose worker, compatible model, webcam permission, and per-player calibration**.
3. To demonstrate student records and the leaderboard, install a **local PostgreSQL service** and initialize a dedicated app database **only with explicit administrator approval**. The Python API is bound to `127.0.0.1:18765`, PostgreSQL normally to port `5432`. See [database/README.md](../database/README.md).
4. For an existing school database, **inspect before migrating**:

       .\tools\diagnose_database_readonly.ps1
       .\database\upgrade_existing_scores.ps1 -CheckOnly

   If the database uses the old student-score schema, follow the upgrade guide's **verified backup + teacher-entered `MIGRATE`** workflow for [`002_add_minigame.sql`](../database/migrations/002_add_minigame.sql). Do not reset, overwrite, or export real records for a classroom demo.

The local Windows user must have configured the app credentials through the game-launched database wizard or the documented manual path. A healthy `/health` response shows a connected **local** database service; a successful editor launch by itself does not.

## 2. Build the offline Windows release (authorized release engineer)

**Build target:** Windows 11 / Windows x64 class, **Godot 4.7.2** with matching Windows **release and debug export templates**. This is a proposed deployment target, **not** a universal compatibility guarantee.

Before creating an export, obtain and approve all of the following:

- Real Godot export templates for version **4.7.2.stable**; Windows x86-64 release and debug binaries must match the engine.
- A reviewed, redistributable `yolo26n-pose.pt` checkpoint and its provenance, license, checksum, and model-inference requirements.
- An official full **CPython 3.11 x64 Windows installer** with `venv` and `ensurepip`, plus a compatible **PostgreSQL 18 x64** offline installer or approved service.
- A complete **CPython 3.11 win_amd64** wheelhouse for [`requirements-offline.txt`](../release/windows/requirements-offline.txt) and all transitive dependencies (including CPU-compatible torch/torchvision, Ultralytics, OpenCV, LAP, Psycopg); no target-PC download fallback.
- Verified redistribution rights/notices for fonts, game assets, audio, third-party packages, Python runtimes and YOLO weights. Do not package the optional private soundtrack or other media without permission. A SHA-256 manifest does **not** confer redistribution rights.

From the source root in **PowerShell**, with approved input paths:

    .\release\windows\Stage-OfflinePrerequisites.ps1 `
      -ModelPath 'C:\approved\yolo26n-pose.pt' `
      -PythonInstallerPath 'C:\approved\python-3.11.9-amd64.exe' `
      -PostgreSqlInstallerPath 'C:\approved\postgresql-18.0-1-windows-x64.exe' `
      -WheelhouseDirectory 'C:\approved\wheels' `
      -LicenseDirectory 'C:\approved\licenses'

These example paths are placeholders for **files that actually exist and are approved**. Staging must generate `release/windows/offline/manifest.json` by hashing real inputs. Never add a fake or empty manifest to bypass the preflight.

Run preflight first, then export only when it succeeds:

    .\release\windows\Build-WindowsRelease.ps1 `
      -GodotExe 'C:\path\Godot_v4.7.2-stable_win64_console.exe' -PreflightOnly

    .\release\windows\Build-WindowsRelease.ps1 `
      -GodotExe 'C:\path\Godot_v4.7.2-stable_win64_console.exe'

**Expected verified output** (only if the build succeeds):

    release/windows/out/KilosGrammar-win-x64/
      KilosGrammar.exe
      KilosGrammar.pck
      manifest.json
      release-manifest.json
      offline/manifest.json
      Setup Offline.cmd
      Play KilosGrammar.cmd
      ...

Read the actual bytes and integrity results rather than assuming the folder exists:

    .\release\windows\Test-ReleasePackage.ps1 `
      -PackageRoot '.\release\windows\out\KilosGrammar-win-x64'

The release script verifies its essential game, worker, database and model files and SHA-256 inventories. Review Windows executable signatures **separately**. The build intentionally refuses to overwrite an existing staging/output folder; preserve it and have an authorized release engineer assess it.

## 3. Install and validate on a separate school computer

**Only follow these steps after a complete, approved package is available.** Transfer the **entire exported folder**, not just `.exe`, to a supported Windows x64 school PC. Disconnect the Internet for the actual acceptance test.

1. The school administrator reviews/install **PostgreSQL 18** locally (or checks the approved service on the PC) and **CPython 3.11 x64** from the provided offline installers. These are explicit separate installers; the KilosGrammar setup script does not silently install PostgreSQL or Python.
2. From the extracted folder (not within a ZIP), run **`Setup Offline.cmd`**. It validates the offline manifest, sets up a **new local Python virtual environment** using only staged wheels, and verifies/copies the YOLO model. A virtual environment copied from a developer PC is not supported.
3. Run **`Play KilosGrammar.cmd`**, which selects the release-local Python environment when starting the exported game. A loose EXE launched directly may not discover the model/runtime correctly.
4. Use the database setup wizard to register/configure a **dedicated local application role** under teacher control. Confirm `CREATE`/`MIGRATE` only when appropriate and after reviewing existing data/backups. Keep the account's DPAPI-protected credentials and backups private.
5. Verify `http://127.0.0.1:18765/health` reports an actually connected local database. Demonstrate the complete setup → calibration → game → completed result → leaderboard workflow on this PC.

The runtime and API are designed for **loopback-only traffic**, not cloud deployment. They still require OS permissions and security controls; local processes on a shared/compromised machine could access locally exposed services. Do not copy another Windows user's DPAPI credential file.

## 4. Acceptance checklist — attach evidence before publication

All boxes are deliberately **unchecked** until validated on the release candidate and recorded by a responsible reviewer. Record the PC model, Windows build, CPU/GPU, webcam, Python/PostgreSQL/Godot versions, model hash, date, tester, and observed result. Use disposable student test records, **never live student data** for destructive QA.

### Packaging and installation

- [ ] Source `VERSION`, GitHub beta label, `docs/BUILD_VERSION.md`, and Windows file/product version metadata are consistent; release source revision recorded.
- [ ] Model, offline installers, wheels, game artwork, audio, fonts and third-party notices have provenance, redistribution permission, and checksums.
- [ ] Offline prerequisite preflight **passes** using the actual release input files and correct export templates.
- [ ] Real EXE, PCK, and both manifest inventories are present; `Test-ReleasePackage.ps1` **passes** with no unexplained/missing files.
- [ ] On a **second Windows x64 PC**, unplugged from the Internet, the full release folder is copied, `Setup Offline.cmd` succeeds, and `Play KilosGrammar.cmd` starts the game **without the Godot editor or downloads**.
- [ ] A reboot does not break local service startup, game launch, model lookup, saved student records or leaderboard access.

### Gameplay, camera, and persistence

- [ ] Webcam permission is granted; local YOLO model loads without a network connection; diagnostic logs show no missing imports/weights.
- [ ] With one student in frame, fresh measured **CENTER → RIGHT → LEFT** calibration succeeds for Catch/Balloon; Human Plane's neutral calibration and required arm posture succeed. Empty frame, occlusion, and extra people do not silently switch student identity.
- [ ] **Catch the Word**, **Balloon Popping**, and **Human Plane** each play and complete in **Seconds and Lives**; movement reaches all three lanes; pause/resume, restart and end-of-round screens work.
- [ ] A repeated student ID with matching details resolves to the correct record; a conflicting ID/name/grade is rejected without overwriting someone else's profile.
- [ ] **Only real completed Play rounds** appear in the correct **minigame/topic/mode/difficulty** leaderboard; tutorial, cancelled, paused and interrupted attempts do not overwrite completed scores.
- [ ] Multiple completed scores remain correct after a **full app close, API restart and Windows reboot**. Any recovery journal behavior is tested without creating duplicates.
- [ ] Teacher-approved CSV export, import (including the eight-column/minigame schema), optional filtered export, and confirmed deletion are tested with disposable data and reviewable backups.

### Safety, accessibility, and evidence

- [ ] The local API binds only to loopback; students' real names/IDs, private CSV, photos/video, backups and database credentials are absent from exported archives, console screenshots and public releases.
- [ ] Live webcam/pose inference and rendering are observed on the actual school hardware, including CPU mode if GPU drivers differ. Do **not** claim unmeasured FPS or pose accuracy.
- [ ] A teacher checks readability at 1280×720 and the target monitor, accessibility of the movement requirements, privacy notice/consent, recovery from a disconnected webcam/database, and a safe backup/restore procedure.
- [ ] Release owner records a signed or otherwise approved handover checklist, limitations, known defects, and rollback instructions before publishing any installer.

## 5. Known boundaries and troubleshooting

- **No installer/manifest present:** This repository checkout does not contain a finished verified package as reviewed on 2026-10-30. Run preflight; do not manufacture a manifest or imply an installer exists.
- **Leaderboard empty after restart:** Confirm the local PostgreSQL service, the API's `/health`, correct Windows account/DPAPI credentials and the current minigame-aware schema. Empty UI does **not** prove rows were deleted. Inspect read-only before migration; see [database/README.md](../database/README.md).
- **Camera unavailable:** Verify physical webcam permission, approved model file, Python interpreter and all installed imports; use the actual target PC for performance assessment. No real-device reliability guarantee is provided by mock frames.
- **Version consistency:** `VERSION`, `project.godot`, and the Windows export preset are aligned for source beta 0.3.0-beta.1, but no completed official Windows binary/export release or disconnected-PC acceptance is established by metadata alone.
- **Score integrity:** Keep the rule that registration is identity-safe and **only completed normal Play rounds** update durable scores. Do not reset databases, bypass confirmation, or confuse a tutorial/aborted run with a valid completion.
- **Scope:** No automatic cloud synchronization, account federation, universal device support, automated pedagogy assessment, or independent classroom research claim is made.

For exact implementation details and flags, consult [release/windows/README.md](../release/windows/README.md) and [database/README.md](../database/README.md); those documents are more detailed than this release-gate summary.
