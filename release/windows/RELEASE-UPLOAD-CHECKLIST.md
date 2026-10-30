# KilosGrammar Windows GitHub Release readiness — 2026-10-30

**Current status: BLOCKED for the promised offline, another-laptop installer.**

Do **not** label the current developer preview as a school-ready or standalone
portable game. The current preview's EXE is a repackaged Godot 4.7.2 editor
binary accompanied by a real exported PCK, not an official release-template
build. It does not contain a working target-local Python/YOLO or PostgreSQL
offline installer/runtime. The developer machine's existing PostgreSQL or
Python installation must never be assumed on the next computer.

## What is genuinely available today

- [x] `release/windows/out/KilosGrammar-v0.3.0-beta.1-EDITOR-PREVIEW-NOT-DEPLOYABLE-win-x64.zip`
- [x] `release/windows/out/KilosGrammar-v0.3.0-beta.1-EDITOR-PREVIEW-NOT-DEPLOYABLE-win-x64.zip.sha256.txt`
- [x] ZIP integrity tested: every one of **28** entries matches the verified
  developer-preview SHA-256 inventory; the full ZIP SHA-256 is
  `DC7F07BD67F6D30BC17412C1E3A72BEB42AFB6D2AD9B4F70389D2BC31ABE191F`
  and length is `228113679` bytes.
- [x] ZIP extracted into a fresh path containing spaces; actual files copied
  to a new `%LOCALAPPDATA%\Programs\Kilos Grammar Release QA ...` location.
  A read-only launch preflight, simulated installation, overwrite/Program
  Files refusal, unknown-file uninstall refusal, uninstall, and preservation
  of external test user data all passed.
- [x] User-provided `release/windows/branding/KILOSGRAMMAR.ico` preserved,
  SHA-256 `A6C85F3056F61D9043794E4B96912AFBB5A9AAC54C893995C7F0417B4DB7F4D8`.
  It is configured for the *future* Windows release export. The preview editor
  binary still uses the editor executable icon.
- [x] ZIP excludes any `.venv`, PostgreSQL cluster, database file, student
  score records, DPAPI credential XML, camera footage, and development export
  template. Existing app folders and global user data were not modified.
- [x] No commit, push, GitHub Release upload, camera run, PostgreSQL login,
  database query, service restart, or deployment performed.

## Before calling any ZIP or Setup.exe a functioning offline release

- [ ] Download/review the exact official **Godot 4.7.2.stable Windows x64**
  release and debug templates, place them in
  `%APPDATA%\Godot\export_templates\4.7.2.stable`, and run the builder's
  template validation. The official complete templates archive is about
  **1,281,349,702 bytes** based on a successful October 30 HTTP HEAD check.
  Downloading this alone does NOT satisfy the Python/PostgreSQL requirements.
- [ ] Review licenses and supply the full **CPython 3.11 x64 offline installer**,
  **PostgreSQL 18 x64 offline installer** and all required redistribution terms.
- [ ] Stage a complete vetted **Windows CPython 3.11 wheelhouse** including
  Ultralytics, compatible Torch + TorchVision, OpenCV, LAP, Psycopg binary and
  every transitive dependency. Validate strictly with `--no-index`, without
  downloading to the school computer.
- [ ] Verify `yolo26n-pose.pt` origin, SHA-256, license and redistribution
  permissions. Verify all game images, fonts and audio have distribution rights.
- [ ] Run `Stage-OfflinePrerequisites.ps1` successfully and verify real
  `release/windows/offline/manifest.json` created from genuine inputs.
- [ ] Run `Build-OfflineRelease.ps1 -PreflightOnly` and then the actual export.
  Require real **Godot Windows release-template EXE** plus PCK, model, Python
  dependencies, database scripts/migrations, offline inputs and
  `manifest.json` verifying all shipped bytes. Never create a fake manifest.
- [ ] On a CLEAN second laptop with Internet disabled, fresh standard Windows
  user, and no developer environment, install to a **fresh writable per-user**
  `%LOCALAPPDATA%\Programs\KilosGrammar` directory (not `Program Files`).
  Run `Setup Offline.cmd` and verify Python3.11 venv/imports without network.
- [ ] Have an administrator review PostgreSQL 18 installation/service, any
  existing port **5432** occupant, database name/role/backups and schema before
  touching records. Review port **18765** occupancy and do not stop or replace
  unrelated processes. DPAPI credentials must stay per-user in LocalAppData.
- [ ] Reboot that other laptop and prove real `KilosGrammar.exe` launch, local
  service health, real webcam permission, on-device YOLO inference, stable
  single-student calibration, Catch/Balloon/Human Plane full rounds, student
  registration, persistent scores, leaderboard and CSV import/export/delete.
- [ ] Test repair/launch, non-admin path containing spaces, port collisions,
  bad/missing runtime, and safe uninstall that preserves student records.
- [ ] Only after all checks, build and TEST a genuine installation experience
  (`Setup.exe` using an actually available Inno Setup/NSIS/WiX tool, or a
  documented equivalent). IExpress alone is an EXE self-extractor, not proof
  of an installed, functioning offline app. No verified installer exists yet.
- [ ] Create an appropriately named non-preview GitHub release tag/version;
  upload the **verified** installable ZIP, installer, checksums and release
  notes. Use the repo's `.../releases/new` interface with authorized credentials.
  Publishing is **not** authorized in the current packaging worker task.

## For internal preview ZIP reproduction only

```powershell
& .\release\windows\Test-PreviewPackage.ps1 `
    -PackageRoot '.\release\windows\staging\KilosGrammar-EDITOR-PREVIEW-win-x64-releaseQA'
& .\release\windows\Build-ReviewedZip.ps1 -AllowPreview
& .\release\windows\Test-ReviewedZip.ps1 `
    -ZipPath '.\release\windows\out\KilosGrammar-v0.3.0-beta.1-EDITOR-PREVIEW-NOT-DEPLOYABLE-win-x64.zip' `
    -PackageRoot '.\release\windows\staging\KilosGrammar-EDITOR-PREVIEW-win-x64-releaseQA' -AllowPreview
```

ZIP building is intentionally **no-overwrite**. Archive contents, checksum and
integrity are checked against the local developer-preview manifest; this is
not a substitute for a code-signing certificate or clean-device acceptance.
